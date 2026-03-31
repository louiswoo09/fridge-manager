import 'package:cloud_firestore/cloud_firestore.dart';

class Ingredient {
  final String id;
  final String uid;
  final String name;
  final String? imageUrl;
  final String category;
  final int quantity;
  final String unit;
  final String storage;
  final DateTime expirationDate;
  final DateTime addedAt;
  final DateTime? lastNotifiedAt;
  final bool isDeleted;
  final DateTime? deletedAt;

  Ingredient({
    required this.id,
    required this.uid,
    required this.name,
    this.imageUrl,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.storage,
    required this.expirationDate,
    required this.addedAt,
    this.lastNotifiedAt,
    this.isDeleted = false,
    this.deletedAt,
  });

  factory Ingredient.fromMap(Map<String, dynamic> map, String id) {
    return Ingredient(
      id: id,
      uid: map['uid'] as String? ?? '',
      name: map['name'] as String? ?? '이름 없음',
      imageUrl: map['image_url'] as String?,
      category: map['category'] as String? ?? '채소',
      quantity: (map['quantity'] is num) ? (map['quantity'] as num).toInt() : 1,
      unit: map['unit'] as String? ?? '개',
      storage: map['storage'] as String? ?? '냉장',
      expirationDate: map['expiration_date'] is Timestamp
          ? (map['expiration_date'] as Timestamp).toDate()
          : DateTime.now().add(const Duration(days: 7)),
      addedAt: map['added_at'] is Timestamp
          ? (map['added_at'] as Timestamp).toDate()
          : DateTime.now(),
      lastNotifiedAt: map['last_notified_at'] is Timestamp
          ? (map['last_notified_at'] as Timestamp).toDate()
          : null,
      isDeleted: map['is_deleted'] as bool? ?? false,
      deletedAt: map['deleted_at'] is Timestamp
          ? (map['deleted_at'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap({bool isCreate = true}) {
    return {
      'uid': uid,
      'name': name,
      if (imageUrl != null) 'image_url': imageUrl,
      'category': category,
      'quantity': quantity,
      'unit': unit,
      'storage': storage,
      'expiration_date': Timestamp.fromDate(expirationDate),
      if (isCreate)
        'added_at': FieldValue.serverTimestamp()
      else
        'added_at': Timestamp.fromDate(addedAt),
      if (lastNotifiedAt != null)
        'last_notified_at': Timestamp.fromDate(lastNotifiedAt!),
      'is_deleted': isDeleted,
      if (deletedAt != null) 'deleted_at': Timestamp.fromDate(deletedAt!),
    };
  }

  Ingredient copyWith({
    String? id,
    String? uid,
    String? name,
    String? imageUrl,
    String? category,
    int? quantity,
    String? unit,
    String? storage,
    DateTime? expirationDate,
    DateTime? addedAt,
    DateTime? lastNotifiedAt,
    bool? isDeleted,
    DateTime? deletedAt,
  }) {
    return Ingredient(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      storage: storage ?? this.storage,
      expirationDate: expirationDate ?? this.expirationDate,
      addedAt: addedAt ?? this.addedAt,
      lastNotifiedAt: lastNotifiedAt ?? this.lastNotifiedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}