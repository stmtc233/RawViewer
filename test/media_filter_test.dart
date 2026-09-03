import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/media_filter.dart';

void main() {
  test('media filters include the expected file kinds', () {
    expect(defaultMediaFilter, MediaFilter.adaptive);
    expect(MediaFilter.adaptive.includes(isRaw: true), isTrue);
    expect(MediaFilter.adaptive.includes(isRaw: false), isTrue);

    expect(MediaFilter.all.includes(isRaw: true), isTrue);
    expect(MediaFilter.all.includes(isRaw: false), isTrue);

    expect(MediaFilter.raw.includes(isRaw: true), isTrue);
    expect(MediaFilter.raw.includes(isRaw: false), isFalse);

    expect(MediaFilter.images.includes(isRaw: true), isFalse);
    expect(MediaFilter.images.includes(isRaw: false), isTrue);
  });

  testWidgets('media filter menu reports counts and changes selection',
      (tester) async {
    var selectedFilter = MediaFilter.adaptive;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              appBar: AppBar(
                actions: [
                  MediaFilterButton(
                    selectedFilter: selectedFilter,
                    adaptiveCount: 4,
                    rawCount: 2,
                    imageCount: 3,
                    onSelected: (filter) {
                      setState(() {
                        selectedFilter = filter;
                      });
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.filter_alt));
    await tester.pumpAndSettle();

    expect(find.text('Adaptive (4)'), findsOneWidget);
    expect(find.text('All (5)'), findsOneWidget);
    expect(find.text('RAW (2)'), findsOneWidget);
    expect(find.text('Standard images (3)'), findsOneWidget);

    final rawMenuItem = find.ancestor(
      of: find.text('RAW (2)'),
      matching: find.byType(CheckedPopupMenuItem<MediaFilter>),
    );
    await tester.tap(rawMenuItem);
    await tester.pumpAndSettle();

    expect(selectedFilter, MediaFilter.raw);
    expect(find.byIcon(Icons.filter_alt), findsOneWidget);
  });
}
