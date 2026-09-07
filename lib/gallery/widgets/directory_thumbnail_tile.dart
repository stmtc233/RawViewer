import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

class DirectoryThumbnailTile extends StatelessWidget {
  const DirectoryThumbnailTile({
    super.key,
    required this.directoryPath,
    required this.onOpen,
  });

  final String directoryPath;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: directoryPath,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(5),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: LayoutBuilder(builder: (context, constraints) {
              if (constraints.maxHeight < 32) {
                return Center(
                    child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(path.basename(directoryPath)),
                ));
              }
              return Column(
                children: [
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Icon(Icons.folder,
                            size: 64, color: Colors.amber.shade600),
                      ),
                    ),
                  ),
                  Text(path.basename(directoryPath),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
