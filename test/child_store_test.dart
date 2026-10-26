import 'package:flutter_test/flutter_test.dart';
import 'package:center_mobile/data/child_store.dart';
import 'package:center_mobile/data/portal.dart';

class _Mem implements SecretStore {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}

void main() {
  const child = PortalUser(
    id: 'c1',
    name: 'ولي',
    nationalId: '',
    portalCode: '',
    role: 'parent',
    tenantId: 't1',
  );

  test('حساب الابن يُحفظ ويُسترجع بهوية الوليّ وكلمته', () async {
    final mem = _Mem();
    final store = ChildStore(secrets: mem, db: () => throw UnimplementedError());
    await store.saveAccount(child, parentId: '123', code: '999999');
    final got = await store.account('c1');
    expect(got?.parentNationalId, '123');
    expect(got?.portalCode, '999999');
    expect(await store.account('c2'), isNull);
  });

  test('بيانات ناقصة لا تُحفظ', () async {
    final mem = _Mem();
    final store = ChildStore(secrets: mem, db: () => throw UnimplementedError());
    await store.saveAccount(child, parentId: '', code: '999999');
    expect(mem.map, isEmpty);
  });
}
