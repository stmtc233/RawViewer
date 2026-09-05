import 'package:flutter/services.dart';

const MethodChannel desktopOpenChannel = MethodChannel('rawviewer/open_paths');
const MethodChannel macOSDirectoryAccessChannel =
    MethodChannel('rawviewer/macos_directory_access');
const MethodChannel windowsShellChannel =
    MethodChannel('rawviewer/windows_shell');
const MethodChannel fileAssociationChannel =
    MethodChannel('rawviewer/file_associations');
