#include "dar_bridge.h"
#include <dar/libdar.hpp>
#include <dar/user_interaction.hpp>
#include <dar/thread_cancellation.hpp>
#include <mutex>
#include <vector>
#include <string>
#include <memory>
#include <cstring>
#include <stdexcept>
#include <set>
#include <CoreFoundation/CoreFoundation.h>

struct entry_record {
    std::string path, link;
    uint64_t size = 0, packed = 0;
    int64_t mtime = 0;
    int kind = 0;
    bool available = true;
};
struct mp_dar_operation {
    std::mutex mutex;
    pthread_t thread = nullptr;
    bool cancelled = false, encrypted = false, password_requested = false;
    std::string interaction_error;
    std::string error;
    std::vector<entry_record> entries;
};
namespace {
std::once_flag initialized;
struct password_needed {};
class interaction final : public libdar::user_interaction {
    mp_dar_operation &op;
public:
    explicit interaction(mp_dar_operation &value) : op(value) {}
private:
    void inherited_message(const std::string &) override {}
    bool inherited_pause(const std::string &message) override {
        op.interaction_error = message;
        return false;
    }
    std::string inherited_get_string(const std::string &message, bool) override {
        op.interaction_error = message;
        throw std::runtime_error(message);
    }
    libdar::secu_string inherited_get_secu_string(const std::string &, bool) override {
        op.password_requested = true;
        throw password_needed();
    }
};
void collect(const std::string &path, const libdar::list_entry &item, void *context) {
    if (item.get_name().empty()) return; // end-of-directory marker
    auto &op = *static_cast<mp_dar_operation *>(context);
    entry_record entry;
    entry.path = path;
    entry.kind = item.is_dir() ? 1 : item.is_file() ? 0 : item.is_symlink() ? 2 : 3;
    entry.link = item.is_symlink() ? item.get_link_target() : "";
    if (item.is_file()) {
        entry.size = std::stoull(item.get_file_size(true));
        libdar::U_64 packed = 0;
        item.get_storage_size_for_data(packed);
        entry.packed = packed;
    }
    entry.mtime = item.is_removed_entry() ? 0 : item.get_last_modif_s();
    entry.available = !item.is_removed_entry() && (!item.is_file() || item.get_data_status() == libdar::saved_status::saved);
    op.entries.push_back(std::move(entry));
}
// Compare names conservatively for the usual case-insensitive macOS volume.
std::string folded(const std::string &value) {
    auto text = CFStringCreateWithBytes(nullptr, reinterpret_cast<const UInt8 *>(value.data()),
                                       value.size(), kCFStringEncodingUTF8, false);
    if (!text) throw std::runtime_error("DAR entry name is not UTF-8");
    auto normalized = CFStringCreateMutableCopy(nullptr, 0, text);
    CFRelease(text);
    if (!normalized) throw std::bad_alloc();
    CFStringNormalize(normalized, kCFStringNormalizationFormD);
    CFStringFold(normalized, kCFCompareCaseInsensitive, nullptr);
    std::vector<char> bytes(CFStringGetMaximumSizeForEncoding(CFStringGetLength(normalized), kCFStringEncodingUTF8) + 1);
    bool success = CFStringGetCString(normalized, bytes.data(), bytes.size(), kCFStringEncodingUTF8);
    CFRelease(normalized);
    if (!success) throw std::runtime_error("Could not normalize DAR entry name");
    return bytes.data();
}
bool safe_path(const std::string &path) {
    if (path.empty() || path[0] == '/' || path.find('\0') != std::string::npos) return false;
    size_t start = 0;
    do {
        size_t end = path.find('/', start);
        auto part = path.substr(start, end == std::string::npos ? end : end - start);
        if (part.empty() || part == "." || part == "..") return false;
        if (end == std::string::npos) return true;
        start = end + 1;
    } while (true);
}
// Revalidate the catalogue on the very archive we will restore, not a previous
// open of a path that another process could replace between operations.
void validate(const mp_dar_operation &op, const char *const *selection, size_t count) {
    std::set<std::string> names, non_directories;
    for (const auto &entry : op.entries) {
        auto name = folded(entry.path);
        if (!safe_path(entry.path) || !names.insert(name).second)
            throw std::runtime_error("Unsafe or conflicting DAR path: " + entry.path);
        if (entry.kind != 1) non_directories.insert(name);
        bool selected = count == 0;
        for (size_t i = 0; i < count; ++i)
            selected |= entry.path == selection[i] || entry.path.rfind(std::string(selection[i]) + "/", 0) == 0;
        if (selected && (!entry.available || entry.kind == 3))
            throw std::runtime_error("DAR entry requires backup restoration or an unsupported file type: " + entry.path);
        if (entry.kind == 2 && !safe_path(entry.link))
            throw std::runtime_error("Unsafe DAR symbolic link: " + entry.path);
    }
    for (const auto &name : names) {
        for (size_t end = name.find('/'); end != std::string::npos; end = name.find('/', end + 1))
            if (non_directories.count(name.substr(0, end)))
                throw std::runtime_error("DAR path descends through a non-directory: " + name);
    }
    for (size_t i = 0; i < count; ++i) {
        bool found = false;
        for (const auto &entry : op.entries) found |= entry.path == selection[i];
        if (!found) throw std::runtime_error("A selected DAR entry is no longer present");
    }
}
class selection_mask final : public libdar::mask {
    std::vector<std::string> paths;
public:
    selection_mask(const char *root, const char *const *selected, size_t count) {
        for (size_t i = 0; i < count; ++i) paths.push_back(std::string(root) + "/" + selected[i]);
    }
    bool is_covered(const std::string &path) const override {
        for (const auto &selected : paths)
            if (path == selected || path.rfind(selected + "/", 0) == 0 || selected.rfind(path + "/", 0) == 0) return true;
        return false;
    }
    std::string dump(const std::string &prefix) const override { return prefix + "MacPacker selection"; }
    libdar::mask *clone() const override { return new selection_mask(*this); }
};
// Clear cancellation before this GCD worker can be reused by another operation.
struct running {
    mp_dar_operation &op;
    running(mp_dar_operation &value) : op(value) {
        std::lock_guard<std::mutex> lock(op.mutex);
        if (op.cancelled) throw std::runtime_error("Cancelled");
        op.thread = pthread_self();
    }
    ~running() {
        std::lock_guard<std::mutex> lock(op.mutex);
        libdar::thread_cancellation::clear_pending_request(op.thread);
        op.thread = nullptr;
    }
};
int perform(mp_dar_operation *op, const char *folder, const char *base, const char *extension, unsigned digits,
            const char *password, const char *destination, const char *const *selection, size_t count) {
    bool opening = true;
    try {
        std::call_once(initialized, [] { libdar::get_version(); });
        running active(*op);
        op->error.clear();
        op->interaction_error.clear();
        op->password_requested = false;
        op->entries.clear();
        libdar::archive_options_read options;
        options.set_multi_threaded_crypto(1);
        options.set_multi_threaded_compress(1);
        options.set_slice_min_digits(libdar::infinint(digits));
        if (password) options.set_crypto_pass(libdar::secu_string(password, std::strlen(password)));
        auto ui = std::make_shared<interaction>(*op);
        libdar::archive archive(ui, libdar::path(folder), base, extension, options);
        opening = false;
        if (!op->interaction_error.empty()) throw std::runtime_error(op->interaction_error);
        archive.op_listing(collect, op, libdar::archive_options_listing());
        // The encrypted constructor requests a password before names can be read.
        op->encrypted = password != nullptr;
        if (destination) {
            validate(*op, selection, count);
            libdar::archive_options_extract extract;
            extract.set_ignore_deleted(true);
            extract.set_warn_over(true);
            if (count) extract.set_subtree(selection_mask(destination, selection, count));
            auto stats = archive.op_extract(libdar::path(destination), extract, nullptr);
            if (!op->interaction_error.empty()) throw std::runtime_error(op->interaction_error);
            if (!stats.get_errored().is_zero() || !stats.get_skipped().is_zero())
                throw std::runtime_error("DAR could not restore every selected entry. A backup reference or a missing slice may be required.");
        }
        return 0;
    } catch (const password_needed &) {
        op->encrypted = true;
        op->error = "DAR archive requires a password";
        return 2;
    } catch (const libdar::Ethread_cancel &) {
        op->error = "Cancelled";
        return 3;
    } catch (const libdar::Erange &error) {
        op->error = error.get_message();
        if (opening && password) return 2; // wrong key and damaged encrypted headers are indistinguishable
    } catch (const libdar::Egeneric &error) {
        op->error = error.get_message();
    } catch (const std::exception &error) {
        op->error = error.what();
    } catch (...) {
        op->error = "Unknown DAR error";
    }
    std::lock_guard<std::mutex> lock(op->mutex);
    if (op->cancelled) return 3;
    // libdar wraps exceptions raised by user_interaction in Elibcall.
    if (op->password_requested) { op->encrypted = true; return 2; }
    return 1;
}
}
extern "C" {
mp_dar_operation *mp_dar_create(void) { try { return new mp_dar_operation(); } catch (...) { return nullptr; } }
void mp_dar_free(mp_dar_operation *op) { delete op; }
void mp_dar_cancel(mp_dar_operation *op) {
    std::lock_guard<std::mutex> lock(op->mutex);
    op->cancelled = true;
    if (op->thread) libdar::thread_cancellation::cancel(op->thread, true, 0);
}
const char *mp_dar_version(void) {
    static const auto version = std::to_string(libdar::LIBDAR_COMPILE_TIME_MAJOR) + "." +
        std::to_string(libdar::LIBDAR_COMPILE_TIME_MEDIUM) + "." + std::to_string(libdar::LIBDAR_COMPILE_TIME_MINOR);
    return version.c_str();
}
int mp_dar_read(mp_dar_operation *op, const char *folder, const char *base, const char *extension, unsigned digits, const char *password) {
    return perform(op, folder, base, extension, digits, password, nullptr, nullptr, 0);
}
int mp_dar_extract(mp_dar_operation *op, const char *folder, const char *base, const char *extension, unsigned digits, const char *password,
                   const char *destination, const char *const *selection, size_t count) {
    return perform(op, folder, base, extension, digits, password, destination, selection, count);
}
const char *mp_dar_error(const mp_dar_operation *op) { return op->error.c_str(); }
size_t mp_dar_count(const mp_dar_operation *op) { return op->entries.size(); }
const char *mp_dar_path(const mp_dar_operation *op, size_t i) { return op->entries.at(i).path.c_str(); }
const char *mp_dar_link(const mp_dar_operation *op, size_t i) { return op->entries.at(i).link.c_str(); }
uint64_t mp_dar_size(const mp_dar_operation *op, size_t i) { return op->entries.at(i).size; }
uint64_t mp_dar_packed_size(const mp_dar_operation *op, size_t i) { return op->entries.at(i).packed; }
int64_t mp_dar_mtime(const mp_dar_operation *op, size_t i) { return op->entries.at(i).mtime; }
int mp_dar_kind(const mp_dar_operation *op, size_t i) { return op->entries.at(i).kind; }
int mp_dar_available(const mp_dar_operation *op, size_t i) { return op->entries.at(i).available; }
int mp_dar_encrypted(const mp_dar_operation *op) { return op->encrypted; }
}
