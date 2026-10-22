import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/data/share_inbox.dart';
import 'package:center_mobile/screens/portal_screens.dart' show sectionsForRoom;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('وحدات الشعبة في صفحة المشاركة', () {
    const all = CourseSection(id: 'a', groupId: 'g', term: 'term_1', title: 'عامة');
    const r1 = CourseSection(id: 'b', groupId: 'g', term: 'term_1', title: 'أ', roomIds: ['r1']);
    const r2 = CourseSection(id: 'c', groupId: 'g', term: 'term_1', title: 'ب', roomIds: ['r2']);
    const both = CourseSection(id: 'd', groupId: 'g', term: 'term_1', title: 'أب', roomIds: ['r1', 'r2']);
    final list = [all, r1, r2, both];

    test('كل الشعب: كل الوحدات', () {
      expect(sectionsForRoom(list, '').map((s) => s.id), ['a', 'b', 'c', 'd']);
    });

    test('شعبة: العامة والمخصصة لها', () {
      expect(sectionsForRoom(list, 'r1').map((s) => s.id), ['a', 'b', 'd']);
      expect(sectionsForRoom(list, 'r2').map((s) => s.id), ['a', 'c', 'd']);
    });
  });

  group('ملف مشارَك', () {
    test('الكبير يُرفض بحد الحجم لا بخطأ القراءة', () {
      final f = SharedFile.fromMap(const {'path': '', 'name': 'كبير.pdf', 'mime': 'application/pdf', 'size': -1});
      expect(f.tooLarge, isTrue);
      expect(f.unreadable, isFalse);
      expect(f.toDraft().ok, isFalse);
    });

    test('صورة بلا امتداد تُعرف من نوعها', () {
      final f = SharedFile.fromMap(const {'path': '/x/1', 'name': 'IMG', 'mime': 'image/jpeg', 'size': 1000});
      expect(f.isImage, isTrue);
      expect(f.toDraft().ok, isTrue);
    });
  });
}
