import 'package:flutter/material.dart';

import '../rclone/models/rclone_file.dart';
import 'theme/tokens.dart';

/// Coarse visual category for a file, used to pick an icon and tint.
enum FileKind {
  folder,
  image,
  video,
  audio,
  pdf,
  archive,
  code,
  document,
  generic,
}

const Set<String> _imageExts = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
  'tiff',
  'svg',
  'avif',
};
const Set<String> _videoExts = {
  'mp4',
  'mov',
  'mkv',
  'webm',
  'avi',
  'm4v',
  'wmv',
  'flv',
  'mpg',
  'mpeg',
};
const Set<String> _audioExts = {
  'mp3',
  'flac',
  'wav',
  'aac',
  'ogg',
  'm4a',
  'opus',
  'wma',
};
const Set<String> _archiveExts = {
  'zip',
  'rar',
  '7z',
  'tar',
  'gz',
  'bz2',
  'xz',
  'zst',
};
const Set<String> _codeExts = {
  'dart',
  'js',
  'ts',
  'json',
  'yaml',
  'yml',
  'html',
  'css',
  'go',
  'py',
  'rs',
  'java',
  'kt',
  'c',
  'cpp',
  'h',
  'sh',
  'md',
  'xml',
  'toml',
};
const Set<String> _documentExts = {
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'txt',
  'rtf',
  'odt',
  'csv',
};

/// Lowercased extension after the last dot, or `''` for dotfiles / no-dot names.
String _extOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// Classifies [f] by extension, then by mime-type prefix as a fallback.
FileKind kindOf(RcloneFile f) {
  if (f.isDir) return FileKind.folder;
  final ext = _extOf(f.name);
  if (_imageExts.contains(ext)) return FileKind.image;
  if (_videoExts.contains(ext)) return FileKind.video;
  if (_audioExts.contains(ext)) return FileKind.audio;
  if (ext == 'pdf') return FileKind.pdf;
  if (_archiveExts.contains(ext)) return FileKind.archive;
  if (_codeExts.contains(ext)) return FileKind.code;
  if (_documentExts.contains(ext)) return FileKind.document;

  final mime = f.mimeType.toLowerCase();
  if (mime.startsWith('image/')) return FileKind.image;
  if (mime.startsWith('video/')) return FileKind.video;
  if (mime.startsWith('audio/')) return FileKind.audio;
  if (mime == 'application/pdf') return FileKind.pdf;

  return FileKind.generic;
}

/// True when [f] is an image whose bytes can be rendered as a thumbnail.
bool isImageThumbnailable(RcloneFile f) => kindOf(f) == FileKind.image;

/// True when [f] is a video we can capture a keyframe from for a thumbnail.
bool isVideoThumbnailable(RcloneFile f) => kindOf(f) == FileKind.video;

/// True when [f] can produce a visual thumbnail (image or video).
bool isThumbnailable(RcloneFile f) =>
    isImageThumbnailable(f) || isVideoThumbnailable(f);

/// Upper bound on an IMAGE original we'll fetch to build a thumbnail. A normal
/// photo is a few MB; skipping absurdly large originals is a cross-platform net
/// against wasted memory/egress (a mis-typed or pathological file, or a cloud
/// image on a platform where placeholder detection is a no-op). Videos stream a
/// keyframe rather than a full read, so they aren't size-gated here — they're
/// gated by the online-only placeholder check instead.
const int kMaxPreviewImageBytes = 128 * 1024 * 1024; // 128 MiB

/// True when [f] appears in the media Gallery view — a non-folder image or
/// video. The SINGLE source of truth for that filter: used by MediaGallery to
/// build its grid AND by `selectAll` so "Select all" in gallery view can never
/// select hidden folders/other files that would then be (recursively) deleted.
bool isGalleryMedia(RcloneFile f) =>
    !f.isDir && (kindOf(f) == FileKind.image || kindOf(f) == FileKind.video);

/// A rounded Material icon representing the file's [FileKind].
IconData iconFor(RcloneFile f) {
  switch (kindOf(f)) {
    case FileKind.folder:
      return Icons.folder_rounded;
    case FileKind.image:
      return Icons.image_rounded;
    case FileKind.video:
      return Icons.movie_rounded;
    case FileKind.audio:
      return Icons.audiotrack_rounded;
    case FileKind.pdf:
      return Icons.picture_as_pdf_rounded;
    case FileKind.archive:
      return Icons.folder_zip_rounded;
    case FileKind.code:
      return Icons.code_rounded;
    case FileKind.document:
      return Icons.description_rounded;
    case FileKind.generic:
      return Icons.insert_drive_file_rounded;
  }
}

/// A semantic tint for the file's icon, drawn from the active palette [c].
Color iconColorFor(RcloneFile f, AircloneColors c) {
  switch (kindOf(f)) {
    case FileKind.folder:
      return c.primary;
    case FileKind.image:
    case FileKind.video:
      return c.secondary;
    case FileKind.audio:
      return c.info;
    case FileKind.pdf:
      return c.error;
    case FileKind.archive:
      return c.warning;
    case FileKind.code:
    case FileKind.document:
    case FileKind.generic:
      return c.textMuted;
  }
}
