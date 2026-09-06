import 'package:flutter/material.dart';

import 'core/rating_filter.dart';
import 'l10n/app_localizations.dart';
import 'ui/app_theme.dart';
import 'ui/desktop_controls.dart';

class RatingFilterButton extends StatelessWidget {
  final RatingFilter selected;
  final ValueChanged<RatingFilter> onSelected;
  final bool showRatings;
  final ValueChanged<bool> onShowRatingsChanged;

  const RatingFilterButton({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.showRatings,
    required this.onShowRatingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DesktopPopupMenuButton<void>(
      tooltip: AppLocalizations.of(context)!.ratingFilterTooltip,
      itemBuilder: (_) => [
        _RatingFilterMenu(
          selected: selected,
          onSelected: onSelected,
          showRatings: showRatings,
          onShowRatingsChanged: onShowRatingsChanged,
        ),
      ],
      child: DesktopPopupMenuTrigger(
        icon: selected == RatingFilter.all ? Icons.star_border : Icons.star,
        selected: selected != RatingFilter.all,
      ),
    );
  }
}

// The popup route owns its selection so it stays interactive even while
// filtering replaces the underlying gallery or preview with a loading view.
class _RatingFilterMenu extends PopupMenuEntry<void> {
  final RatingFilter selected;
  final ValueChanged<RatingFilter> onSelected;
  final bool showRatings;
  final ValueChanged<bool> onShowRatingsChanged;

  const _RatingFilterMenu({
    required this.selected,
    required this.onSelected,
    required this.showRatings,
    required this.onShowRatingsChanged,
  });

  @override
  double get height => 328;

  @override
  bool represents(void value) => false;

  @override
  State<_RatingFilterMenu> createState() => _RatingFilterMenuState();
}

class _RatingFilterMenuState extends State<_RatingFilterMenu> {
  late RatingFilter _selected = widget.selected;
  late bool _showRatings = widget.showRatings;

  Widget _checkbox(String label, bool checked, VoidCallback onToggle) =>
      SizedBox(
        height: 40,
        child: CheckboxListTile(
          value: checked,
          onChanged: (_) => onToggle(),
          title: Text(label,
              style:
                  const TextStyle(fontSize: 12, color: RawViewerColors.text)),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          dense: true,
          visualDensity: VisualDensity.compact,
          activeColor: RawViewerColors.accent,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: 220,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var index = 0; index < RatingFilter.values.length; index++)
          _checkbox(
            index == 0
                ? l10n.ratingFilterAll
                : index == 1
                    ? l10n.exifRatingUnrated
                    : l10n.ratingFilterStars(index - 1),
            _selected.isSelected(RatingFilter.values[index]),
            () {
              setState(() =>
                  _selected = _selected.toggle(RatingFilter.values[index]));
              widget.onSelected(_selected);
            },
          ),
        const Divider(height: 8),
        _checkbox(l10n.previewRatingsTitle, _showRatings, () {
          setState(() => _showRatings = !_showRatings);
          widget.onShowRatingsChanged(_showRatings);
        }),
      ]),
    );
  }
}
