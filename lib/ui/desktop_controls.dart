import 'package:flutter/material.dart';

import 'app_theme.dart';

const double desktopControlSize = 34;

class DesktopPopupMenuButton<T> extends StatelessWidget {
  final String tooltip;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final Widget child;
  final T? initialValue;
  final Offset offset;
  final bool enabled;

  const DesktopPopupMenuButton({
    super.key,
    required this.tooltip,
    required this.itemBuilder,
    required this.child,
    this.onSelected,
    this.initialValue,
    this.offset = Offset.zero,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      itemBuilder: itemBuilder,
      initialValue: initialValue,
      onSelected: onSelected,
      enabled: enabled,
      padding: EdgeInsets.zero,
      offset: offset,
      color: RawViewerColors.raisedSurface,
      shape: rawViewerPopupMenuShape,
      elevation: 14,
      shadowColor: Colors.black87,
      surfaceTintColor: Colors.transparent,
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      popUpAnimationStyle: rawViewerPopupMenuAnimationStyle,
      borderRadius: BorderRadius.circular(5),
      child: child,
    );
  }
}

class DesktopPopupMenuTrigger extends StatelessWidget {
  final IconData icon;
  final bool selected;

  const DesktopPopupMenuTrigger({
    super.key,
    required this.icon,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: desktopControlSize,
      height: desktopControlSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? RawViewerColors.accentMuted : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(
          icon,
          color: selected ? RawViewerColors.accent : RawViewerColors.mutedText,
          size: 19,
        ),
      ),
    );
  }
}

class DesktopPopupMenuLabelTrigger extends StatelessWidget {
  final IconData icon;
  final String label;

  const DesktopPopupMenuLabelTrigger({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 66),
      child: SizedBox(
        height: desktopControlSize,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: RawViewerColors.mutedText, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: RawViewerColors.mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

PopupMenuItem<T> desktopPopupMenuItem<T>({
  required T value,
  required String label,
  IconData? icon,
  bool selected = false,
  bool enabled = true,
}) {
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    height: 36,
    padding: EdgeInsets.zero,
    child: _DesktopPopupMenuItemContent(
      icon: icon,
      label: label,
      selected: selected,
      enabled: enabled,
    ),
  );
}

class _DesktopPopupMenuItemContent extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool selected;
  final bool enabled;

  const _DesktopPopupMenuItemContent({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final foreground =
        enabled ? RawViewerColors.text : RawViewerColors.mutedBorder;
    final iconColor =
        enabled ? RawViewerColors.mutedText : RawViewerColors.mutedBorder;

    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF1B292A) : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: icon == null ? null : Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.check,
              size: 16,
              color: RawViewerColors.accent,
            ),
          ],
        ],
      ),
    );
  }
}

class DesktopIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  const DesktopIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = selected
        ? RawViewerColors.accent
        : enabled
            ? RawViewerColors.mutedText
            : RawViewerColors.mutedBorder;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: desktopControlSize,
        height: desktopControlSize,
        child: Material(
          color: selected ? RawViewerColors.accentMuted : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: onPressed,
            hoverColor: RawViewerColors.raisedSurface,
            splashColor: RawViewerColors.accentMuted,
            child: Icon(icon, color: color, size: 19),
          ),
        ),
      ),
    );
  }
}

class DesktopCommandButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool emphasized;

  const DesktopCommandButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground =
        emphasized ? RawViewerColors.text : RawViewerColors.mutedText;
    final background = emphasized
        ? RawViewerColors.accentMuted
        : RawViewerColors.raisedSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        hoverColor:
            emphasized ? const Color(0xFF285B54) : RawViewerColors.border,
        onTap: onPressed,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color:
                  emphasized ? const Color(0xFF37776D) : RawViewerColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: foreground),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DesktopSettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const DesktopSettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: RawViewerColors.mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: RawViewerColors.surface,
              border: Border.all(color: RawViewerColors.mutedBorder),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class DesktopSettingsOption extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const DesktopSettingsOption({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? const Color(0xFF1B292A) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: RawViewerColors.raisedSurface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? RawViewerColors.accent
                          : RawViewerColors.mutedText,
                      width: selected ? 5 : 1,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: RawViewerColors.text,
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: RawViewerColors.mutedText,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopSettingsRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget control;

  const DesktopSettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: RawViewerColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: RawViewerColors.mutedText,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: control,
          ),
        ],
      ),
    );
  }
}
