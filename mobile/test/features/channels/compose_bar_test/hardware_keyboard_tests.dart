part of '../compose_bar_test.dart';

void hardwareKeyboardTests() {
  Future<void> withComposer(
    WidgetTester tester,
    Future<void> Function(TextEditingController, List<String>) exercise, {
    TargetPlatform platform = TargetPlatform.iOS,
    String draft = 'Hello',
    String? threadHeadId,
    Size size = const Size(1024, 768),
    Future<void> Function()? delivery,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      final sent = <String>[];
      await tester.pumpWidget(
        _buildComposeBar(
          uploadService: _testUploadService(nostr.Keys.generate().nsec),
          threadHeadId: threadHeadId,
          onSend: (content, mentionPubkeys, {mediaTags = const []}) async {
            sent.add(content);
            await delivery?.call();
          },
        ),
      );
      await _expandComposer(tester);
      await tester.enterText(find.byType(TextField), draft);
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      await exercise(controller, sent);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('iOS hardware keyboard composer', () {
    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ]) {
      for (final thread in [false, true]) {
        testWidgets('${key.keyLabel} sends once (thread=$thread)', (
          tester,
        ) async {
          await withComposer(tester, (controller, sent) async {
            expect(await tester.sendKeyEvent(key), isTrue);
            await tester.pumpAndSettle();
            expect(sent, ['Hello']);
            expect(controller.text, isEmpty);
          }, threadHeadId: thread ? 'thread-1' : null);
        });
      }
    }

    testWidgets('Shift+Return inserts a newline at the selection', (
      tester,
    ) async {
      await withComposer(tester, (controller, sent) async {
        controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 4,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(sent, isEmpty);
        expect(controller.text, 'H\no');
        expect(controller.selection, const TextSelection.collapsed(offset: 2));
      });
    });

    testWidgets('held Return does not send again or insert a newline', (
      tester,
    ) async {
      await withComposer(tester, (controller, sent) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Next draft');
        await tester.pumpAndSettle();
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(sent, ['Hello']);
        expect(controller.text, 'Next draft');
      });
    });

    testWidgets('Return does not send an empty draft', (tester) async {
      await withComposer(tester, (controller, sent) async {
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
        await tester.pumpAndSettle();
        expect(sent, isEmpty);
        expect(controller.text, isEmpty);
      }, draft: '');
    });

    testWidgets('Return sends newly typed text before the next frame', (
      tester,
    ) async {
      await withComposer(tester, (controller, sent) async {
        await tester.enterText(find.byType(TextField), 'Hello');
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
        await tester.pumpAndSettle();
        expect(sent, ['Hello']);
        expect(controller.text, isEmpty);
      }, draft: '');
    });

    testWidgets('Return sends in a narrow iPad window too', (tester) async {
      await withComposer(tester, (controller, sent) async {
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
        await tester.pumpAndSettle();
        expect(sent, ['Hello']);
      }, size: const Size(600, 768));
    });

    testWidgets('Shift+Numpad Enter inserts a newline at the caret', (
      tester,
    ) async {
      await withComposer(tester, (controller, sent) async {
        controller.selection = const TextSelection.collapsed(offset: 5);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftRight);
        expect(
          await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter),
          isTrue,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftRight);
        await tester.pumpAndSettle();
        expect(sent, isEmpty);
        expect(controller.text, 'Hello\n');
        expect(controller.selection, const TextSelection.collapsed(offset: 6));
      });
    });

    testWidgets('Return preserves a new draft while a send is pending', (
      tester,
    ) async {
      final delivery = Completer<void>();
      try {
        await withComposer(tester, (controller, sent) async {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(sent, ['Hello']);
          await tester.enterText(find.byType(TextField), 'Next draft');
          await tester.pump();
          expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
          await tester.pump();
          expect(sent, ['Hello']);
          expect(controller.text, 'Next draft');
          delivery.complete();
          await tester.pumpAndSettle();
        }, delivery: () => delivery.future);
      } finally {
        if (!delivery.isCompleted) delivery.complete();
      }
    });

    testWidgets('Return leaves active IME composition to the input method', (
      tester,
    ) async {
      await withComposer(tester, (controller, sent) async {
        controller.value = const TextEditingValue(
          text: 'Hello',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        );
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
        await tester.pumpAndSettle();
        expect(sent, isEmpty);
        expect(controller.text, 'Hello');
        expect(controller.value.composing, const TextRange(start: 0, end: 5));
      });
    });

    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      testWidgets('${modifier.keyLabel}+Return does not send', (tester) async {
        await withComposer(tester, (controller, sent) async {
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(modifier);
          await tester.pumpAndSettle();
          expect(sent, isEmpty);
          expect(controller.text, 'Hello');
        });
      });
    }

    testWidgets('software Return remains a newline action without sending', (
      tester,
    ) async {
      await withComposer(tester, (controller, sent) async {
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.textInputAction, TextInputAction.newline);
        await tester.testTextInput.receiveAction(TextInputAction.newline);
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'Hello\n',
            selection: TextSelection.collapsed(offset: 6),
          ),
        );
        await tester.pumpAndSettle();
        expect(sent, isEmpty);
        expect(controller.text, 'Hello\n');
      });
    });

    testWidgets('Android hardware Return does not send', (tester) async {
      await withComposer(tester, (controller, sent) async {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(sent, isEmpty);
      }, platform: TargetPlatform.android);
    });
  });
}
