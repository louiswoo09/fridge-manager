import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ingredient.dart';

class IngredientService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<List<Ingredient>> getIngredients({bool sortByExpiration = true}) {
    final uid = _auth.currentUser!.uid;

    Query<Map<String, dynamic>> query = _db
        .collection('users')
        .doc(uid)
        .collection('ingredients')
        .where('is_deleted', isEqualTo: false);

    query = sortByExpiration
        ? query.orderBy('expiration_date', descending: false)
        : query.orderBy('added_at', descending: true);

    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => Ingredient.fromMap(doc.data(), doc.id))
          .toList(),
    );
  }
  Future<void> cleanOldDeletedItems() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('ingredients')
        .where('is_deleted', isEqualTo: true)
        .get();

    final batch = FirebaseFirestore.instance.batch();

    for (var doc in snapshot.docs) {
      final deletedAt = doc['deleted_at'];

      if (deletedAt == null) continue;

      final diff =
          DateTime.now().difference(deletedAt.toDate()).inDays;

      if (diff >= 7) {
        batch.delete(doc.reference);
      }
    }

    await batch.commit();
  }
}
