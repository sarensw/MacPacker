# CSevenZip Source Curation Manifest

Every `.c` and `.cpp` file compiled by the `CSevenZip` SPM target, listed with rationale.
Update `Package.swift` `cSevenZipSources` array whenever this file changes.

## vendor/7zip/C/ -- Base C utilities

- `vendor/7zip/C/7zCrc.c` -- CRC calculation
- `vendor/7zip/C/7zCrcOpt.c` -- Optimised CRC
- `vendor/7zip/C/Alloc.c` -- Memory allocation
- `vendor/7zip/C/CpuArch.c` -- CPU architecture detection
- `vendor/7zip/C/Delta.c` -- Delta filter
- `vendor/7zip/C/LzmaDec.c` -- LZMA decoder
- `vendor/7zip/C/Lzma2Dec.c` -- LZMA2 decoder
- `vendor/7zip/C/Lzma2DecMt.c` -- LZMA2 multi-thread decoder stub
- `vendor/7zip/C/LzmaEnc.c` -- LZMA encoder (needed by some decoders)
- `vendor/7zip/C/Lzma2Enc.c` -- LZMA2 encoder (needed by some decoders)
- `vendor/7zip/C/LzFind.c` -- LZ match finder
- `vendor/7zip/C/LzFindMt.c` -- LZ match finder multi-thread stub
- `vendor/7zip/C/LzFindOpt.c` -- LZ match finder optimised
- `vendor/7zip/C/7zAlloc.c` -- 7z-specific allocator
- `vendor/7zip/C/7zArcIn.c` -- 7z archive input
- `vendor/7zip/C/7zBuf.c` -- Buffer utilities
- `vendor/7zip/C/7zBuf2.c` -- Buffer utilities 2
- `vendor/7zip/C/7zDec.c` -- 7z decoder
- `vendor/7zip/C/7zFile.c` -- File I/O
- `vendor/7zip/C/7zStream.c` -- Stream utilities
- `vendor/7zip/C/Aes.c` -- AES encryption (software fallback; hw_stubs.c provides HW stubs)
- `vendor/7zip/C/Bcj2.c` -- BCJ2 filter
- `vendor/7zip/C/Bcj2Enc.c` -- BCJ2 encoder
- `vendor/7zip/C/Blake2s.c` -- BLAKE2s hash
- `vendor/7zip/C/Bra.c` -- Branch filter
- `vendor/7zip/C/Bra86.c` -- x86 branch filter
- `vendor/7zip/C/BraIA64.c` -- IA64 branch filter
- `vendor/7zip/C/BwtSort.c` -- BWT sort
- `vendor/7zip/C/DllSecur.c` -- DLL security stubs
- `vendor/7zip/C/HuffEnc.c` -- Huffman encoder
- `vendor/7zip/C/Lzma86Dec.c` -- LZMA86 decoder
- `vendor/7zip/C/Lzma86Enc.c` -- LZMA86 encoder
- `vendor/7zip/C/LzmaLib.c` -- LZMA library wrapper
- `vendor/7zip/C/Md5.c` -- MD5 hash
- `vendor/7zip/C/MtCoder.c` -- Multi-thread coder stub
- `vendor/7zip/C/MtDec.c` -- Multi-thread decoder stub
- `vendor/7zip/C/Ppmd7.c` -- PPMd model
- `vendor/7zip/C/Ppmd7aDec.c` -- PPMd7a decoder
- `vendor/7zip/C/Ppmd7Dec.c` -- PPMd7 decoder
- `vendor/7zip/C/Ppmd7Enc.c` -- PPMd7 encoder
- `vendor/7zip/C/Ppmd8.c` -- PPMd8 model
- `vendor/7zip/C/Ppmd8Dec.c` -- PPMd8 decoder
- `vendor/7zip/C/Ppmd8Enc.c` -- PPMd8 encoder
- `vendor/7zip/C/Sha1.c` -- SHA1 hash (software fallback; hw_stubs.c provides HW stubs)
- `vendor/7zip/C/Sha256.c` -- SHA256 hash (software fallback; hw_stubs.c provides HW stubs)
- `vendor/7zip/C/Sha3.c` -- SHA3 hash
- `vendor/7zip/C/Sha512.c` -- SHA512 hash (software fallback; hw_stubs.c provides HW stubs)
- `vendor/7zip/C/Sort.c` -- Sort utilities
- `vendor/7zip/C/Threads.c` -- Threading stubs (no-op under _7ZIP_ST)
- `vendor/7zip/C/Xxh64.c` -- XXH64 hash
- `vendor/7zip/C/Xz.c` -- XZ utilities
- `vendor/7zip/C/XzCrc64.c` -- XZ CRC64
- `vendor/7zip/C/XzCrc64Opt.c` -- Optimised XZ CRC64
- `vendor/7zip/C/XzDec.c` -- XZ decoder
- `vendor/7zip/C/XzEnc.c` -- XZ encoder
- `vendor/7zip/C/XzIn.c` -- XZ input
- `vendor/7zip/C/ZstdDec.c` -- Zstandard decoder

## vendor/7zip/CPP/Common/ -- Core C++ utilities

- `vendor/7zip/CPP/Common/CRC.cpp` -- CRC wrapper
- `vendor/7zip/CPP/Common/CrcReg.cpp` -- CRC registration
- `vendor/7zip/CPP/Common/IntToString.cpp` -- Integer to string conversion
- `vendor/7zip/CPP/Common/MyString.cpp` -- UString (UTF-16 string class)
- `vendor/7zip/CPP/Common/MyVector.cpp` -- Vector container
- `vendor/7zip/CPP/Common/MyXml.cpp` -- XML parsing
- `vendor/7zip/CPP/Common/MyMap.cpp` -- Map container
- `vendor/7zip/CPP/Common/NewHandler.cpp` -- Custom new handler
- `vendor/7zip/CPP/Common/StringConvert.cpp` -- String encoding conversion
- `vendor/7zip/CPP/Common/UTFConvert.cpp` -- UTF conversion
- `vendor/7zip/CPP/Common/Wildcard.cpp` -- Wildcard matching
- `vendor/7zip/CPP/Common/MyWindows.cpp` -- Windows API stubs for POSIX
- `vendor/7zip/CPP/Common/DynLimBuf.cpp` -- Dynamic limited buffer
- `vendor/7zip/CPP/Common/StringToInt.cpp` -- String to integer conversion
- `vendor/7zip/CPP/Common/C_FileIO.cpp` -- C file I/O wrapper
- `vendor/7zip/CPP/Common/Sha256Prepare.cpp` -- SHA256 preparation
- `vendor/7zip/CPP/Common/Sha1Prepare.cpp` -- SHA1 preparation
- `vendor/7zip/CPP/Common/Sha512Prepare.cpp` -- SHA512 preparation
- `vendor/7zip/CPP/Common/Sha1Reg.cpp` -- SHA1 registration
- `vendor/7zip/CPP/Common/Sha256Reg.cpp` -- SHA256 registration
- `vendor/7zip/CPP/Common/Sha3Reg.cpp` -- SHA3 registration
- `vendor/7zip/CPP/Common/Sha512Reg.cpp` -- SHA512 registration
- `vendor/7zip/CPP/Common/Md5Reg.cpp` -- MD5 registration
- `vendor/7zip/CPP/Common/CksumReg.cpp` -- Checksum registration
- `vendor/7zip/CPP/Common/XzCrc64Init.cpp` -- XZ CRC64 initialisation
- `vendor/7zip/CPP/Common/XzCrc64Reg.cpp` -- XZ CRC64 registration
- `vendor/7zip/CPP/Common/Xxh64Reg.cpp` -- XXH64 registration
- `vendor/7zip/CPP/Common/LzFindPrepare.cpp` -- LZ find preparation

## vendor/7zip/CPP/Windows/ -- Windows API stubs for POSIX

- `vendor/7zip/CPP/Windows/FileDir.cpp` -- Directory operations
- `vendor/7zip/CPP/Windows/FileFind.cpp` -- File search
- `vendor/7zip/CPP/Windows/FileIO.cpp` -- File I/O
- `vendor/7zip/CPP/Windows/FileName.cpp` -- File name handling
- `vendor/7zip/CPP/Windows/PropVariant.cpp` -- PROPVARIANT utilities
- `vendor/7zip/CPP/Windows/PropVariantConv.cpp` -- PROPVARIANT conversion
- `vendor/7zip/CPP/Windows/PropVariantUtils.cpp` -- PROPVARIANT utilities
- `vendor/7zip/CPP/Windows/Synchronization.cpp` -- Synchronisation stubs
- `vendor/7zip/CPP/Windows/System.cpp` -- System information
- `vendor/7zip/CPP/Windows/SystemInfo.cpp` -- System info
- `vendor/7zip/CPP/Windows/TimeUtils.cpp` -- Time utilities
- `vendor/7zip/CPP/Windows/FileLink.cpp` -- File link operations
- `vendor/7zip/CPP/Windows/FileSystem.cpp` -- File system utilities
- `vendor/7zip/CPP/Windows/ErrorMsg.cpp` -- Error messages
- `vendor/7zip/CPP/Windows/DLL.cpp` -- DLL stubs

## vendor/7zip/CPP/7zip/Common/ -- Stream interfaces and utilities

- `vendor/7zip/CPP/7zip/Common/CreateCoder.cpp` -- Codec factory
- `vendor/7zip/CPP/7zip/Common/CWrappers.cpp` -- C wrapper interfaces
- `vendor/7zip/CPP/7zip/Common/FileStreams.cpp` -- File stream implementations
- `vendor/7zip/CPP/7zip/Common/FilterCoder.cpp` -- Filter coder
- `vendor/7zip/CPP/7zip/Common/InBuffer.cpp` -- Input buffer
- `vendor/7zip/CPP/7zip/Common/InOutTempBuffer.cpp` -- Temp I/O buffer
- `vendor/7zip/CPP/7zip/Common/LimitedStreams.cpp` -- Limited streams
- `vendor/7zip/CPP/7zip/Common/MethodId.cpp` -- Method ID utilities
- `vendor/7zip/CPP/7zip/Common/MethodProps.cpp` -- Method properties
- `vendor/7zip/CPP/7zip/Common/OffsetStream.cpp` -- Offset stream
- `vendor/7zip/CPP/7zip/Common/OutBuffer.cpp` -- Output buffer
- `vendor/7zip/CPP/7zip/Common/ProgressUtils.cpp` -- Progress utilities
- `vendor/7zip/CPP/7zip/Common/PropId.cpp` -- Property ID table
- `vendor/7zip/CPP/7zip/Common/StreamObjects.cpp` -- Stream object implementations
- `vendor/7zip/CPP/7zip/Common/StreamUtils.cpp` -- Stream utility functions
- `vendor/7zip/CPP/7zip/Common/UniqBlocks.cpp` -- Unique blocks
- `vendor/7zip/CPP/7zip/Common/VirtThread.cpp` -- Virtual thread
- `vendor/7zip/CPP/7zip/Common/FilePathAutoRename.cpp` -- File path auto rename
- `vendor/7zip/CPP/7zip/Common/LockedStream.cpp` -- Locked stream
- `vendor/7zip/CPP/7zip/Common/MemBlocks.cpp` -- Memory blocks
- `vendor/7zip/CPP/7zip/Common/MultiOutStream.cpp` -- Multi output stream
- `vendor/7zip/CPP/7zip/Common/OutMemStream.cpp` -- Output memory stream
- `vendor/7zip/CPP/7zip/Common/ProgressMt.cpp` -- Progress multi-thread
- `vendor/7zip/CPP/7zip/Common/StreamBinder.cpp` -- Stream binder

## vendor/7zip/CPP/7zip/Archive/ -- Format handlers

- `vendor/7zip/CPP/7zip/Archive/ArchiveExports.cpp` -- Archive format exports
- `vendor/7zip/CPP/7zip/Archive/DllExports2.cpp` -- DLL exports
- `vendor/7zip/CPP/7zip/Archive/Common/CoderMixer2.cpp` -- Coder mixer
- `vendor/7zip/CPP/7zip/Archive/Common/DummyOutStream.cpp` -- Dummy output stream
- `vendor/7zip/CPP/7zip/Archive/Common/FindSignature.cpp` -- Signature finder
- `vendor/7zip/CPP/7zip/Archive/Common/HandlerOut.cpp` -- Handler output
- `vendor/7zip/CPP/7zip/Archive/Common/InStreamWithCRC.cpp` -- Input stream with CRC
- `vendor/7zip/CPP/7zip/Archive/Common/ItemNameUtils.cpp` -- Item name utilities
- `vendor/7zip/CPP/7zip/Archive/Common/MultiStream.cpp` -- Multi stream
- `vendor/7zip/CPP/7zip/Archive/Common/OutStreamWithCRC.cpp` -- Output stream with CRC
- `vendor/7zip/CPP/7zip/Archive/Common/OutStreamWithSha1.cpp` -- Output stream with SHA1
- `vendor/7zip/CPP/7zip/Archive/Common/ParseProperties.cpp` -- Parse properties

### 7z format
- `vendor/7zip/CPP/7zip/Archive/7z/7zDecode.cpp` -- 7z decoder
- `vendor/7zip/CPP/7zip/Archive/7z/7zExtract.cpp` -- 7z extractor
- `vendor/7zip/CPP/7zip/Archive/7z/7zHandler.cpp` -- 7z handler
- `vendor/7zip/CPP/7zip/Archive/7z/7zHandlerOut.cpp` -- 7z handler output
- `vendor/7zip/CPP/7zip/Archive/7z/7zHeader.cpp` -- 7z header
- `vendor/7zip/CPP/7zip/Archive/7z/7zIn.cpp` -- 7z input
- `vendor/7zip/CPP/7zip/Archive/7z/7zRegister.cpp` -- 7z registration
- `vendor/7zip/CPP/7zip/Archive/7z/7zProperties.cpp` -- 7z properties
- `vendor/7zip/CPP/7zip/Archive/7z/7zSpecStream.cpp` -- 7z special stream
- `vendor/7zip/CPP/7zip/Archive/7z/7zCompressionMode.cpp` -- 7z compression mode
- `vendor/7zip/CPP/7zip/Archive/7z/7zEncode.cpp` -- 7z encoder
- `vendor/7zip/CPP/7zip/Archive/7z/7zFolderInStream.cpp` -- 7z folder input stream
- `vendor/7zip/CPP/7zip/Archive/7z/7zOut.cpp` -- 7z output
- `vendor/7zip/CPP/7zip/Archive/7z/7zUpdate.cpp` -- 7z update

### Zip format
- `vendor/7zip/CPP/7zip/Archive/Zip/ZipHandler.cpp` -- Zip handler
- `vendor/7zip/CPP/7zip/Archive/Zip/ZipHandlerOut.cpp` -- Zip handler output
- `vendor/7zip/CPP/7zip/Archive/Zip/ZipIn.cpp` -- Zip input
- `vendor/7zip/CPP/7zip/Archive/Zip/ZipItem.cpp` -- Zip item
- `vendor/7zip/CPP/7zip/Archive/Zip/ZipRegister.cpp` -- Zip registration
- `vendor/7zip/CPP/7zip/Archive/Zip/ZipAddCommon.cpp` -- Zip add common
- `vendor/7zip/CPP/7zip/Archive/Zip/ZipOut.cpp` -- Zip output
- `vendor/7zip/CPP/7zip/Archive/Zip/ZipUpdate.cpp` -- Zip update

### GZip format
- `vendor/7zip/CPP/7zip/Archive/GzHandler.cpp` -- GZip handler

### BZip2 format
- `vendor/7zip/CPP/7zip/Archive/Bz2Handler.cpp` -- BZip2 handler

### Xz format
- `vendor/7zip/CPP/7zip/Archive/XzHandler.cpp` -- XZ handler

### Tar format
- `vendor/7zip/CPP/7zip/Archive/Tar/TarHandler.cpp` -- Tar handler
- `vendor/7zip/CPP/7zip/Archive/Tar/TarHandlerOut.cpp` -- Tar handler output
- `vendor/7zip/CPP/7zip/Archive/Tar/TarHeader.cpp` -- Tar header
- `vendor/7zip/CPP/7zip/Archive/Tar/TarIn.cpp` -- Tar input
- `vendor/7zip/CPP/7zip/Archive/Tar/TarRegister.cpp` -- Tar registration
- `vendor/7zip/CPP/7zip/Archive/Tar/TarOut.cpp` -- Tar output
- `vendor/7zip/CPP/7zip/Archive/Tar/TarUpdate.cpp` -- Tar update

### Rar format
- `vendor/7zip/CPP/7zip/Archive/Rar/RarHandler.cpp` -- Rar handler
- `vendor/7zip/CPP/7zip/Archive/Rar/Rar5Handler.cpp` -- Rar5 handler

### Other archive handlers (required for detection)
- `vendor/7zip/CPP/7zip/Archive/LzmaHandler.cpp` -- LZMA handler
- `vendor/7zip/CPP/7zip/Archive/SplitHandler.cpp` -- Split handler
- `vendor/7zip/CPP/7zip/Archive/PpmdHandler.cpp` -- PPMd handler
- `vendor/7zip/CPP/7zip/Archive/HandlerCont.cpp` -- Handler container
- `vendor/7zip/CPP/7zip/Archive/DeflateProps.cpp` -- Deflate properties
- `vendor/7zip/CPP/7zip/Archive/ZHandler.cpp` -- Z handler
- `vendor/7zip/CPP/7zip/Archive/ZstdHandler.cpp` -- Zstandard handler
- `vendor/7zip/CPP/7zip/Archive/Cab/CabBlockInStream.cpp` -- Cab block input stream
- `vendor/7zip/CPP/7zip/Archive/Cab/CabHandler.cpp` -- Cab handler
- `vendor/7zip/CPP/7zip/Archive/Cab/CabHeader.cpp` -- Cab header
- `vendor/7zip/CPP/7zip/Archive/Cab/CabIn.cpp` -- Cab input
- `vendor/7zip/CPP/7zip/Archive/Cab/CabRegister.cpp` -- Cab registration
- `vendor/7zip/CPP/7zip/Archive/Iso/IsoHandler.cpp` -- ISO handler
- `vendor/7zip/CPP/7zip/Archive/Iso/IsoHeader.cpp` -- ISO header
- `vendor/7zip/CPP/7zip/Archive/Iso/IsoIn.cpp` -- ISO input
- `vendor/7zip/CPP/7zip/Archive/Iso/IsoRegister.cpp` -- ISO registration
- `vendor/7zip/CPP/7zip/Archive/Nsis/NsisDecode.cpp` -- NSIS decode
- `vendor/7zip/CPP/7zip/Archive/Nsis/NsisHandler.cpp` -- NSIS handler
- `vendor/7zip/CPP/7zip/Archive/Nsis/NsisIn.cpp` -- NSIS input
- `vendor/7zip/CPP/7zip/Archive/Nsis/NsisRegister.cpp` -- NSIS registration
- `vendor/7zip/CPP/7zip/Archive/Udf/UdfHandler.cpp` -- UDF handler
- `vendor/7zip/CPP/7zip/Archive/Udf/UdfIn.cpp` -- UDF input
- `vendor/7zip/CPP/7zip/Archive/Wim/WimHandler.cpp` -- WIM handler
- `vendor/7zip/CPP/7zip/Archive/Wim/WimHandlerOut.cpp` -- WIM handler output
- `vendor/7zip/CPP/7zip/Archive/Wim/WimIn.cpp` -- WIM input
- `vendor/7zip/CPP/7zip/Archive/Wim/WimRegister.cpp` -- WIM registration
- `vendor/7zip/CPP/7zip/Archive/XarHandler.cpp` -- XAR handler
- `vendor/7zip/CPP/7zip/Archive/ArHandler.cpp` -- AR handler
- `vendor/7zip/CPP/7zip/Archive/ArjHandler.cpp` -- ARJ handler
- `vendor/7zip/CPP/7zip/Archive/Base64Handler.cpp` -- Base64 handler
- `vendor/7zip/CPP/7zip/Archive/CpioHandler.cpp` -- CPIO handler
- `vendor/7zip/CPP/7zip/Archive/CramfsHandler.cpp` -- CramFS handler
- `vendor/7zip/CPP/7zip/Archive/DmgHandler.cpp` -- DMG handler
- `vendor/7zip/CPP/7zip/Archive/ElfHandler.cpp` -- ELF handler
- `vendor/7zip/CPP/7zip/Archive/ExtHandler.cpp` -- EXT handler
- `vendor/7zip/CPP/7zip/Archive/FatHandler.cpp` -- FAT handler
- `vendor/7zip/CPP/7zip/Archive/FlvHandler.cpp` -- FLV handler
- `vendor/7zip/CPP/7zip/Archive/GptHandler.cpp` -- GPT handler
- `vendor/7zip/CPP/7zip/Archive/HfsHandler.cpp` -- HFS handler
- `vendor/7zip/CPP/7zip/Archive/IhexHandler.cpp` -- IHEX handler
- `vendor/7zip/CPP/7zip/Archive/LzhHandler.cpp` -- LZH handler
- `vendor/7zip/CPP/7zip/Archive/MachoHandler.cpp` -- Mach-O handler
- `vendor/7zip/CPP/7zip/Archive/MbrHandler.cpp` -- MBR handler
- `vendor/7zip/CPP/7zip/Archive/MslzHandler.cpp` -- MSLZ handler
- `vendor/7zip/CPP/7zip/Archive/MubHandler.cpp` -- MUB handler
- `vendor/7zip/CPP/7zip/Archive/NtfsHandler.cpp` -- NTFS handler
- `vendor/7zip/CPP/7zip/Archive/PeHandler.cpp` -- PE handler
- `vendor/7zip/CPP/7zip/Archive/QcowHandler.cpp` -- QCOW handler
- `vendor/7zip/CPP/7zip/Archive/RpmHandler.cpp` -- RPM handler
- `vendor/7zip/CPP/7zip/Archive/SquashfsHandler.cpp` -- SquashFS handler
- `vendor/7zip/CPP/7zip/Archive/SwfHandler.cpp` -- SWF handler
- `vendor/7zip/CPP/7zip/Archive/VdiHandler.cpp` -- VDI handler
- `vendor/7zip/CPP/7zip/Archive/VhdHandler.cpp` -- VHD handler
- `vendor/7zip/CPP/7zip/Archive/VhdxHandler.cpp` -- VHDX handler
- `vendor/7zip/CPP/7zip/Archive/VmdkHandler.cpp` -- VMDK handler
- `vendor/7zip/CPP/7zip/Archive/ApfsHandler.cpp` -- APFS handler
- `vendor/7zip/CPP/7zip/Archive/ApmHandler.cpp` -- APM handler
- `vendor/7zip/CPP/7zip/Archive/AvbHandler.cpp` -- AVB handler
- `vendor/7zip/CPP/7zip/Archive/ComHandler.cpp` -- COM handler
- `vendor/7zip/CPP/7zip/Archive/Chm/ChmHandler.cpp` -- CHM handler
- `vendor/7zip/CPP/7zip/Archive/Chm/ChmIn.cpp` -- CHM input
- `vendor/7zip/CPP/7zip/Archive/LpHandler.cpp` -- LP handler
- `vendor/7zip/CPP/7zip/Archive/LvmHandler.cpp` -- LVM handler
- `vendor/7zip/CPP/7zip/Archive/SparseHandler.cpp` -- Sparse handler
- `vendor/7zip/CPP/7zip/Archive/UefiHandler.cpp` -- UEFI handler

## vendor/7zip/CPP/7zip/Compress/ -- Codecs

- `vendor/7zip/CPP/7zip/Compress/Bcj2Coder.cpp` -- BCJ2 coder
- `vendor/7zip/CPP/7zip/Compress/Bcj2Register.cpp` -- BCJ2 registration
- `vendor/7zip/CPP/7zip/Compress/BcjCoder.cpp` -- BCJ coder
- `vendor/7zip/CPP/7zip/Compress/BcjRegister.cpp` -- BCJ registration
- `vendor/7zip/CPP/7zip/Compress/BitlDecoder.cpp` -- Bit length decoder
- `vendor/7zip/CPP/7zip/Compress/BranchMisc.cpp` -- Branch misc
- `vendor/7zip/CPP/7zip/Compress/BranchRegister.cpp` -- Branch registration
- `vendor/7zip/CPP/7zip/Compress/ByteSwap.cpp` -- Byte swap
- `vendor/7zip/CPP/7zip/Compress/BZip2Crc.cpp` -- BZip2 CRC
- `vendor/7zip/CPP/7zip/Compress/BZip2Decoder.cpp` -- BZip2 decoder
- `vendor/7zip/CPP/7zip/Compress/BZip2Encoder.cpp` -- BZip2 encoder
- `vendor/7zip/CPP/7zip/Compress/BZip2Register.cpp` -- BZip2 registration
- `vendor/7zip/CPP/7zip/Compress/CodecExports.cpp` -- Codec exports
- `vendor/7zip/CPP/7zip/Compress/CopyCoder.cpp` -- Copy coder
- `vendor/7zip/CPP/7zip/Compress/CopyRegister.cpp` -- Copy registration
- `vendor/7zip/CPP/7zip/Compress/Deflate64Register.cpp` -- Deflate64 registration
- `vendor/7zip/CPP/7zip/Compress/DeflateDecoder.cpp` -- Deflate decoder
- `vendor/7zip/CPP/7zip/Compress/DeflateEncoder.cpp` -- Deflate encoder
- `vendor/7zip/CPP/7zip/Compress/DeflateRegister.cpp` -- Deflate registration
- `vendor/7zip/CPP/7zip/Compress/DeltaFilter.cpp` -- Delta filter
- `vendor/7zip/CPP/7zip/Compress/ImplodeDecoder.cpp` -- Implode decoder
- `vendor/7zip/CPP/7zip/Compress/ImplodeHuffmanDecoder.cpp` -- Implode Huffman decoder
- `vendor/7zip/CPP/7zip/Compress/LzfseDecoder.cpp` -- LZFSE decoder
- `vendor/7zip/CPP/7zip/Compress/LzhDecoder.cpp` -- LZH decoder
- `vendor/7zip/CPP/7zip/Compress/Lzma2Decoder.cpp` -- LZMA2 decoder
- `vendor/7zip/CPP/7zip/Compress/Lzma2Encoder.cpp` -- LZMA2 encoder
- `vendor/7zip/CPP/7zip/Compress/Lzma2Register.cpp` -- LZMA2 registration
- `vendor/7zip/CPP/7zip/Compress/LzmaDecoder.cpp` -- LZMA decoder
- `vendor/7zip/CPP/7zip/Compress/LzmaEncoder.cpp` -- LZMA encoder
- `vendor/7zip/CPP/7zip/Compress/LzmaRegister.cpp` -- LZMA registration
- `vendor/7zip/CPP/7zip/Compress/LzmsDecoder.cpp` -- LZMS decoder
- `vendor/7zip/CPP/7zip/Compress/LzOutWindow.cpp` -- LZ output window
- `vendor/7zip/CPP/7zip/Compress/LzxDecoder.cpp` -- LZX decoder
- `vendor/7zip/CPP/7zip/Compress/PpmdDecoder.cpp` -- PPMd decoder
- `vendor/7zip/CPP/7zip/Compress/PpmdEncoder.cpp` -- PPMd encoder
- `vendor/7zip/CPP/7zip/Compress/PpmdRegister.cpp` -- PPMd registration
- `vendor/7zip/CPP/7zip/Compress/PpmdZip.cpp` -- PPMd ZIP wrapper
- `vendor/7zip/CPP/7zip/Compress/QuantumDecoder.cpp` -- Quantum decoder
- `vendor/7zip/CPP/7zip/Compress/Rar1Decoder.cpp` -- RAR1 decoder
- `vendor/7zip/CPP/7zip/Compress/Rar2Decoder.cpp` -- RAR2 decoder
- `vendor/7zip/CPP/7zip/Compress/Rar3Decoder.cpp` -- RAR3 decoder
- `vendor/7zip/CPP/7zip/Compress/Rar3Vm.cpp` -- RAR3 virtual machine
- `vendor/7zip/CPP/7zip/Compress/Rar5Decoder.cpp` -- RAR5 decoder
- `vendor/7zip/CPP/7zip/Compress/RarCodecsRegister.cpp` -- RAR codecs registration
- `vendor/7zip/CPP/7zip/Compress/ShrinkDecoder.cpp` -- Shrink decoder
- `vendor/7zip/CPP/7zip/Compress/XpressDecoder.cpp` -- Xpress decoder
- `vendor/7zip/CPP/7zip/Compress/XzDecoder.cpp` -- XZ decoder
- `vendor/7zip/CPP/7zip/Compress/XzEncoder.cpp` -- XZ encoder
- `vendor/7zip/CPP/7zip/Compress/ZDecoder.cpp` -- Z decoder
- `vendor/7zip/CPP/7zip/Compress/ZlibDecoder.cpp` -- Zlib decoder
- `vendor/7zip/CPP/7zip/Compress/ZlibEncoder.cpp` -- Zlib encoder
- `vendor/7zip/CPP/7zip/Compress/ZstdDecoder.cpp` -- Zstandard decoder

## vendor/7zip/CPP/7zip/Crypto/ -- Crypto codecs

- `vendor/7zip/CPP/7zip/Crypto/7zAes.cpp` -- 7z AES encryption
- `vendor/7zip/CPP/7zip/Crypto/7zAesRegister.cpp` -- 7z AES registration
- `vendor/7zip/CPP/7zip/Crypto/HmacSha1.cpp` -- HMAC-SHA1
- `vendor/7zip/CPP/7zip/Crypto/HmacSha256.cpp` -- HMAC-SHA256
- `vendor/7zip/CPP/7zip/Crypto/MyAes.cpp` -- AES wrapper
- `vendor/7zip/CPP/7zip/Crypto/MyAesReg.cpp` -- AES registration
- `vendor/7zip/CPP/7zip/Crypto/Pbkdf2HmacSha1.cpp` -- PBKDF2 HMAC-SHA1
- `vendor/7zip/CPP/7zip/Crypto/RandGen.cpp` -- Random generator
- `vendor/7zip/CPP/7zip/Crypto/Rar20Crypto.cpp` -- RAR 2.0 crypto
- `vendor/7zip/CPP/7zip/Crypto/Rar5Aes.cpp` -- RAR5 AES
- `vendor/7zip/CPP/7zip/Crypto/RarAes.cpp` -- RAR AES
- `vendor/7zip/CPP/7zip/Crypto/WzAes.cpp` -- WinZip AES
- `vendor/7zip/CPP/7zip/Crypto/ZipCrypto.cpp` -- ZIP classic crypto
- `vendor/7zip/CPP/7zip/Crypto/ZipStrong.cpp` -- ZIP strong crypto

## Bridge files (Sources/CSevenZip/)

- `Sources/CSevenZip/sevenzip_bridge.cpp` -- C bridge between 7-zip C++ internals and Swift
- `Sources/CSevenZip/hw_stubs.c` -- Stub implementations for hardware-accelerated AES/SHA/SwapBytes functions

## Excluded directories

- `vendor/7zip/CPP/7zip/UI/` -- CLI and GUI frontends
- `vendor/7zip/CPP/7zip/Bundles/` -- Standalone binary bundles
- `vendor/7zip/DOC/` -- Documentation
- `vendor/7zip/Asm/` -- Assembly optimisations (C fallbacks used via _7ZIP_ST)
- `vendor/7zip/CPP/7zip/Compress/DllExports2Compress.cpp` -- DLL export for standalone module
- `vendor/7zip/CPP/7zip/Compress/DllExportsCompress.cpp` -- DLL export for standalone module

## Excluded files (with rationale)

- `vendor/7zip/C/AesOpt.c` -- Uses architecture-specific intrinsics (SSE/ARM NEON) that don't cross-compile under SPM; hw_stubs.c provides stub functions
- `vendor/7zip/C/Sha1Opt.c` -- Same (architecture-specific intrinsics)
- `vendor/7zip/C/Sha256Opt.c` -- Same (architecture-specific intrinsics)
- `vendor/7zip/C/Sha512Opt.c` -- Same (architecture-specific intrinsics)
- `vendor/7zip/C/SwapBytes.c` -- Same (architecture-specific intrinsics)
- `vendor/7zip/CPP/Windows/MemoryLock.cpp` -- Uses Windows-only APIs (HANDLE, HMODULE)
- `vendor/7zip/CPP/Windows/NationalTime.cpp` -- Uses Windows-only APIs (LCID)
