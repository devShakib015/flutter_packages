/// Real files on Flutter Web, via the File System Access API.
library;

export 'src/platform.dart' show DirectoryHandle, FileHandle, FileSystemAccess;
export 'src/types.dart'
    show
        DirectoryEntry,
        FilePermission,
        FilePickerType,
        FileSystemAccessException,
        FileSystemAccessSupport,
        FileSystemFailure,
        NamedBytes,
        PermissionDeniedException,
        UnsupportedByBrowserException;
