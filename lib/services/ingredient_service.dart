import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ingredient.dart';

class IngredientService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<List<Ingredient>> getIngredients({
    bool sortByExpiration = true,
  }) {
    final uid = _auth.currentUser?.uid ?? 'h4in0wUpPbYPEAWfc4zgE21FvN02';
    //if (uid == null) return Stream.value([]);

    Query<Map<String, dynamic>> query = _db
        .collection('Ingredients')
        .where('uid', isEqualTo: uid)
        .where('is_deleted', isEqualTo: false);

    query = sortByExpiration
        ? query.orderBy('expiration_date', descending: false)
        : query.orderBy('added_at', descending: true);

    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => Ingredient.fromMap(doc.data(), doc.id))
        .toList());
  }
}

/*
팀원한테 전달할 메모.

- uid는 서비스 내부에서 자동으로 가져오니까 따로 넘길 필요 없음
- 실시간으로 데이터 자동 갱신됨 (Stream)
- 논리 삭제된 항목은 자동으로 제외됨
- 유통기한 오름차순 정렬 자동 적용됨
- where + orderBy 같이 쓰면 index 필요 (에러 뜨면 링크 눌러서 생성)
*/