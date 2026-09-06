import 'package:flutter/material.dart';

import 'core/rating_filter.dart';
import 'l10n/app_localizations.dart';

class RatingBadge extends StatelessWidget {
  final String filePath;
  final RatingRepository repository;

  const RatingBadge(
      {super.key, required this.filePath, required this.repository});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int?>(
      key: ValueKey(filePath),
      future: repository.load(filePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 18);
        }
        final rating = snapshot.data ?? 0;
        final l10n = AppLocalizations.of(context)!;
        final label = snapshot.data == null
            ? l10n.exifRatingMissing
            : rating == 0
                ? l10n.exifRatingUnrated
                : l10n.ratingFilterStars(rating);
        return Tooltip(
          message: label,
          child: Semantics(
            label: '${l10n.exifRating}: $label',
            child: Container(
              height: 18,
              constraints: const BoxConstraints(maxWidth: 86),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xCC151719),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var star = 1; star <= 5; star++)
                      Icon(star <= rating ? Icons.star : Icons.star_border,
                          size: 14,
                          color:
                              star <= rating ? Colors.amber : Colors.white70),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
