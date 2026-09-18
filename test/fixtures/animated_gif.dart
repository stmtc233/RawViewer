import 'dart:convert';
import 'dart:typed_data';

/// Two full 2x2 frames: red, then green; 100 ms each, looping forever.
Uint8List twoFrameGif() => base64Decode(
    'R0lGODlhAgACAIAAAP8AAAD/ACH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACwAAAAAAgACAAACAoRRACH5BAAKAAAALAAAAAACAAIAAAICjFMAOw==');
