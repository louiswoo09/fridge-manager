import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ingredient.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});
  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {

  Stream<List<Ingredient>> getDeletedIngredients() {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('ingredients')
        .where('is_deleted', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Ingredient.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> restoreItem(String id) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('ingredients')
        .doc(id)
        .update({'is_deleted': false, 'deleted_at': null});
  }

  Future<void> deleteForever(BuildContext context, String id) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('삭제'),
        content: const Text('정말로 완전히 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('ingredients')
        .doc(id)
        .delete();
  }

  Future<void> deleteAll() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('전체 삭제'),
        content: const Text('휴지통의 모든 항목을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('ingredients')
        .where('is_deleted', isEqualTo: true)
        .get();

    final batch = FirebaseFirestore.instance.batch();

    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('휴지통'),
        actions: [
          TextButton(
            onPressed: deleteAll,
            child: const Text(
              '전체 삭제',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Ingredient>>(
        stream: getDeletedIngredients(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('휴지통이 비어 있습니다.'));
          }

          final items = snapshot.data!;

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];

              return ListTile(
                title: Text(item.name),

                trailing: Wrap(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore),
                      onPressed: () => restoreItem(item.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      onPressed: () => deleteForever(context, item.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
