import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FridgeService {
  String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('로그인이 필요해요');
    }
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _fridgesRef =>
      FirebaseFirestore.instance.collection('fridges');

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  /// 6자리 초대 코드 생성 (헷갈리는 0/O, 1/I 제외)
  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// 새 냉장고 생성 (소유자 = 현재 사용자)
  Future<String> createFridge(String name) async {
    String code;
    while (true) {
      code = _generateInviteCode();
      final dup = await _fridgesRef
          .where('inviteCode', isEqualTo: code)
          .limit(1)
          .get();
      if (dup.docs.isEmpty) break;
    }

    final doc = await _fridgesRef.add({
      'name': name,
      'ownerUid': _uid,
      'memberUids': [_uid],
      'inviteCode': code,
      'createdAt': Timestamp.now(),
    });

    return doc.id;
  }

  /// 현재 사용자가 속한 냉장고 목록
  Stream<List<Map<String, dynamic>>> watchMyFridges() {
    return _fridgesRef
        .where('memberUids', arrayContains: _uid)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) {
            final data = d.data();
            data['_id'] = d.id;
            return data;
          }).toList(),
        );
  }

  /// 단일 냉장고 정보
  Stream<Map<String, dynamic>?> watchFridge(String fridgeId) {
    return _fridgesRef.doc(fridgeId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data()!;
      data['_id'] = doc.id;
      return data;
    });
  }

  /// 활성 냉장고 ID
  Stream<String?> watchActiveFridgeId() {
    return _userRef.snapshots().map((doc) {
      if (!doc.exists) return null;
      return doc.data()?['activeFridgeId']?.toString();
    });
  }

  /// 활성 냉장고 변경
  Future<void> setActiveFridge(String fridgeId) async {
    await _userRef.set({'activeFridgeId': fridgeId}, SetOptions(merge: true));
  }

  /// 초대 코드로 냉장고 참여
  Future<String> joinByInviteCode(String code) async {
    final snap = await _fridgesRef
        .where('inviteCode', isEqualTo: code.toUpperCase())
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      throw StateError('유효하지 않은 코드입니다');
    }

    final doc = snap.docs.first;
    final data = doc.data();
    final memberUids = List<String>.from(data['memberUids'] ?? []);

    if (memberUids.contains(_uid)) {
      throw StateError('이미 참여한 냉장고입니다');
    }

    await doc.reference.update({
      'memberUids': FieldValue.arrayUnion([_uid]),
    });

    return doc.id;
  }

/// 초대 코드 재발급 (소유자만)
Future<String> regenerateInviteCode(String fridgeId) async {
  final doc = await _fridgesRef.doc(fridgeId).get();
  if (!doc.exists) {
    throw StateError('냉장고를 찾을 수 없습니다');
  }

  final ownerUid = doc.data()?['ownerUid']?.toString();
  if (ownerUid != _uid) {
    throw StateError('소유자만 코드를 재발급할 수 있습니다');
  }

  // 중복 안 되는 새 코드 생성
  String code;
  while (true) {
    code = _generateInviteCode();
    final dup = await _fridgesRef
        .where('inviteCode', isEqualTo: code)
        .limit(1)
        .get();
    if (dup.docs.isEmpty) break;
  }

  await doc.reference.update({'inviteCode': code});
  return code;
}

  /// 사용자 displayName 자동 설정 (없으면 기본값)
  Future<void> ensureDisplayName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await _userRef.get();
    if (doc.exists &&
        (doc.data()?['displayName'] as String?)?.isNotEmpty == true) {
      return;
    }

    final defaultName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : '사용자 ${user.uid.substring(0, 6)}';

    await _userRef.set({'displayName': defaultName}, SetOptions(merge: true));
  }

  /// 멤버 호칭 설정 (소유자만). 빈 문자열이면 호칭 제거.
  Future<void> setMemberAlias(
    String fridgeId,
    String targetUid,
    String alias,
  ) async {
    final doc = await _fridgesRef.doc(fridgeId).get();
    if (!doc.exists) return;

    final ownerUid = doc.data()?['ownerUid']?.toString();
    if (ownerUid != _uid) {
      throw StateError('소유자만 호칭을 설정할 수 있습니다');
    }

    if (alias.trim().isEmpty) {
      await doc.reference.update({
        'memberAliases.$targetUid': FieldValue.delete(),
      });
    } else {
      await doc.reference.update({'memberAliases.$targetUid': alias.trim()});
    }
  }

  /// 핀 상태 Stream (사용자의 핀 목록)
  Stream<Set<String>> watchPinnedFridges() {
    return _userRef.snapshots().map((doc) {
      if (!doc.exists) return <String>{};
      final list = doc.data()?['pinnedFridges'] as List?;
      return list?.map((e) => e.toString()).toSet() ?? <String>{};
    });
  }

  /// 핀 토글
  Future<void> togglePin(String fridgeId) async {
    final doc = await _userRef.get();
    final list =
        (doc.data()?['pinnedFridges'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    if (list.contains(fridgeId)) {
      list.remove(fridgeId);
    } else {
      list.add(fridgeId);
    }

    await _userRef.set({'pinnedFridges': list}, SetOptions(merge: true));
  }

  /// 냉장고에서 본인 떠나기
  Future<void> leaveFridge(String fridgeId) async {
    final doc = await _fridgesRef.doc(fridgeId).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final memberUids = List<String>.from(data['memberUids'] ?? []);
    final ownerUid = data['ownerUid']?.toString();

    // 마지막 멤버면 냉장고 삭제
    if (memberUids.length <= 1) {
      await _deleteFridgeCompletely(fridgeId);
      return;
    }

    // 소유자가 떠나면 다음 멤버를 소유자로
    if (ownerUid == _uid) {
      final nextOwner = memberUids.firstWhere((uid) => uid != _uid);
      await doc.reference.update({
        'memberUids': FieldValue.arrayRemove([_uid]),
        'ownerUid': nextOwner,
      });
    } else {
      await doc.reference.update({
        'memberUids': FieldValue.arrayRemove([_uid]),
      });
    }
  }

  /// 냉장고 완전 삭제 (소유자만)
  Future<void> deleteFridge(String fridgeId) async {
    final doc = await _fridgesRef.doc(fridgeId).get();
    if (!doc.exists) return;

    final ownerUid = doc.data()?['ownerUid']?.toString();
    if (ownerUid != _uid) {
      throw StateError('소유자만 삭제할 수 있습니다');
    }

    await _deleteFridgeCompletely(fridgeId);
  }

  /// 멤버 강퇴 (소유자만)
  Future<void> kickMember(String fridgeId, String targetUid) async {
    final doc = await _fridgesRef.doc(fridgeId).get();
    if (!doc.exists) return;

    final ownerUid = doc.data()?['ownerUid']?.toString();
    if (ownerUid != _uid) {
      throw StateError('소유자만 강퇴할 수 있습니다');
    }
    if (targetUid == _uid) {
      throw StateError('자기 자신은 강퇴할 수 없습니다');
    }

    await doc.reference.update({
      'memberUids': FieldValue.arrayRemove([targetUid]),
    });
  }

  /// 냉장고 이름 변경
  Future<void> renameFridge(String fridgeId, String newName) async {
    await _fridgesRef.doc(fridgeId).update({'name': newName});
  }

  /// 앱 시작 시 활성 냉장고 보장 (없으면 기본 냉장고 생성 + 마이그레이션)
  Future<void> ensureActiveFridge() async {
    final userDoc = await _userRef.get();

    // 이미 activeFridgeId 있고 그 냉장고가 존재 + 본인이 멤버면 OK
    if (userDoc.exists) {
      final activeFridgeId = userDoc.data()?['activeFridgeId']?.toString();
      if (activeFridgeId != null && activeFridgeId.isNotEmpty) {
        final fridgeDoc = await _fridgesRef.doc(activeFridgeId).get();
        if (fridgeDoc.exists) {
          final memberUids = List<String>.from(
            fridgeDoc.data()?['memberUids'] ?? [],
          );
          if (memberUids.contains(_uid)) {
            return; // 정상
          }
        }
      }
    }

    // 본인이 속한 다른 냉장고 있나?
    final mine = await _fridgesRef
        .where('memberUids', arrayContains: _uid)
        .limit(1)
        .get();

    if (mine.docs.isNotEmpty) {
      await setActiveFridge(mine.docs.first.id);
      return;
    }

    // 없으면 기본 냉장고 생성
    final fridgeId = await createFridge('내 냉장고');
    await _migrateLegacyData(fridgeId);
    await setActiveFridge(fridgeId);
  }

  /// 기존 users/uid 직속의 ingredients, cart를 새 냉장고로 이동
  Future<void> _migrateLegacyData(String fridgeId) async {
    final legacyIngredientsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('ingredients');
    final legacyCartRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('cart');

    final newIngredientsRef = _fridgesRef
        .doc(fridgeId)
        .collection('ingredients');
    final newCartRef = _fridgesRef.doc(fridgeId).collection('cart');

    // ingredients 복사
    final ingredients = await legacyIngredientsRef.get();
    for (final doc in ingredients.docs) {
      await newIngredientsRef.doc(doc.id).set(doc.data());
    }

    // cart 복사
    final cartItems = await legacyCartRef.get();
    for (final doc in cartItems.docs) {
      await newCartRef.doc(doc.id).set(doc.data());
    }

    // 복사 끝나면 원본 삭제
    for (final doc in ingredients.docs) {
      await doc.reference.delete();
    }
    for (final doc in cartItems.docs) {
      await doc.reference.delete();
    }
  }

  /// 냉장고 완전 삭제 헬퍼 (subcollection 포함)
  Future<void> _deleteFridgeCompletely(String fridgeId) async {
    final fridgeDoc = _fridgesRef.doc(fridgeId);

    final ingredients = await fridgeDoc.collection('ingredients').get();
    for (final d in ingredients.docs) {
      await d.reference.delete();
    }

    final cart = await fridgeDoc.collection('cart').get();
    for (final d in cart.docs) {
      await d.reference.delete();
    }

    await fridgeDoc.delete();
  }
}
