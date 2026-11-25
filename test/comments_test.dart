import 'dart:io';

import 'package:codename/activity/activity.dart';
import 'package:codename/activity/activity_repository.dart';
import 'package:codename/comments/comment.dart';
import 'package:codename/comments/comment_repository.dart';
import 'package:codename/comments/task_comments.dart';
import 'package:codename/tasks/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  late ActivityRepository activity;
  late TaskRepository tasks;
  late CommentRepository comments;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('comments_test');
    store = LocalStore.inMemory();
    activity = ActivityRepository(store, actorId: () => 'me');
    tasks = TaskRepository(store, dir);
    comments = CommentRepository(
      store,
      onAdded: (c) => activity.recordComment(tasks.get(c.taskId), c),
    );
  });

  tearDown(() async {
    await store.close();
    dir.deleteSync(recursive: true);
  });

  group('comments', () {
    test('added to a task, oldest first; blank ones are skipped', () {
      final t = tasks.create(title: 'Ship it', originId: 'p');
      final first = comments.add(
        taskId: t.id,
        authorId: 'me',
        body: 'First',
        now: DateTime.utc(2026, 11, 24, 10),
      )!;
      comments.add(
        taskId: t.id,
        authorId: 'sam',
        body: 'Second',
        now: DateTime.utc(2026, 11, 24, 9),
      );
      comments.add(taskId: 'other', authorId: 'me', body: 'Elsewhere');
      expect(comments.add(taskId: t.id, authorId: 'me', body: '  \n '), isNull);
      expect(
        [for (final c in comments.forTask(t.id)) c.body],
        ['Second', 'First'],
      );
      comments.delete(first.id);
      expect(comments.forTask(t.id).single.body, 'Second');
    });

    test('counts per task, live', () async {
      final seen = <Map<String, int>>[];
      final sub = comments.watchCounts().listen(seen.add);
      await pumpEventQueue();
      comments.add(taskId: 'a', authorId: 'me', body: 'One');
      final two = comments.add(taskId: 'a', authorId: 'me', body: 'Two')!;
      comments.add(taskId: 'b', authorId: 'me', body: 'Three');
      expect(comments.counts(), {'a': 2, 'b': 1});
      comments.delete(two.id);
      await pumpEventQueue();
      expect(seen.first, isEmpty);
      expect(seen.last, {'a': 1, 'b': 1});
      await sub.cancel();
    });

    test('only paragraphs, bold and links are kept', () {
      expect(
        commentMarkdown(
          '# Plan\n\nShip **it** *now* ~~later~~ [here](https://x.io)\n\n'
          '- one\n- two',
        ),
        'Plan\n\nShip **it** now later [here](https://x.io)\n\none\ntwo',
      );
    });

    test('round-trips through JSON; plain text for previews', () {
      final c = Comment(
        id: 'c',
        taskId: 't',
        authorId: 'me',
        body: 'Ship **it**\n\nsee [docs](https://x.io)',
        createdAt: DateTime.utc(2026, 11, 24),
      );
      final back = Comment.fromJson('c', c.toJson())!;
      expect((back.taskId, back.authorId, back.body), ('t', 'me', c.body));
      expect(back.createdAt, c.createdAt);
      expect(c.plainText, 'Ship it see docs');
      expect(Comment.fromJson('x', {'body': 'no task'}), isNull);
    });
  });

  group('activity', () {
    test("tells the assignee, with a preview, but not if it's theirs", () {
      final t = tasks.create(
        title: 'Ship it',
        originId: 'p',
        assigneeId: 'you',
      );
      comments.add(taskId: t.id, authorId: 'me', body: 'Looks **good**');
      final a = activity.current('you').single;
      expect(a.kind, ActivityKind.commented);
      expect(a.actorId, 'me');
      expect(a.excerpt, 'Looks good');
      expect(a.taskTitle, 'Ship it');

      comments.add(taskId: t.id, authorId: 'you', body: 'Thanks');
      expect(activity.current('you'), hasLength(1), reason: 'their own');

      final unassigned = tasks.create(title: 'Later', originId: 'p');
      comments.add(taskId: unassigned.id, authorId: 'me', body: 'Hm');
      expect(activity.current('you'), hasLength(1));
    });

    test('a long comment is cut short in its preview', () {
      final t = tasks.create(title: 'T', originId: 'p', assigneeId: 'you');
      comments.add(taskId: t.id, authorId: 'me', body: 'word ' * 60);
      final excerpt = activity.current('you').single.excerpt!;
      expect(
        excerpt.length,
        lessThanOrEqualTo(ActivityRepository.excerptLength + 1),
      );
      expect(excerpt.endsWith('…'), isTrue);
    });

    test('the excerpt survives a round-trip; old records have none', () {
      final a = Activity(
        id: 'a',
        recipientId: 'you',
        actorId: 'me',
        taskId: 't',
        taskTitle: 'T',
        kind: ActivityKind.commented,
        excerpt: 'Hi',
        createdAt: DateTime.utc(2026),
      );
      expect(Activity.fromJson('a', a.toJson())!.excerpt, 'Hi');
      expect(
        Activity.fromJson('a', {...a.toJson()}..remove('excerpt'))!.excerpt,
        isNull,
      );
    });
  });

  test('when a comment was posted', () {
    final now = DateTime(2026, 11, 24, 18);
    expect(commentTime(DateTime(2026, 11, 24, 15, 42), now), 'Today, 3:42 PM');
    expect(
      commentTime(DateTime(2026, 11, 23, 9, 5), now),
      'Yesterday, 9:05 AM',
    );
    expect(
      commentTime(DateTime(2026, 11, 17, 15, 42), now),
      'Nov 17, 2026, 3:42 PM',
    );
  });
}
