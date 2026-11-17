part of '../channel_detail_page_test.dart';

void textSelectionTests() {
  testWidgets('Select text enters and leaves selection for that message', (
    tester,
  ) async {
    MessageLongPressInkWell row() => tester.widget<MessageLongPressInkWell>(
      find.byKey(const ValueKey('message-row-msg1')),
    );

    await tester.pumpWidget(
      _buildTestable(
        messages: [
          _textMsg(
            id: 'msg1',
            pubkey: 'alice',
            content: 'hello selectable world',
          ),
        ],
        users: const {
          'alice': UserProfile(pubkey: 'alice', displayName: 'Alice'),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsNothing);

    await tester.longPress(find.byKey(const ValueKey('message-row-msg1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select text'));
    await tester.pumpAndSettle();

    expect(find.text('Select text'), findsNothing);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(row().enabled, isFalse);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsNothing);
    expect(row().enabled, isTrue);
  });
}
