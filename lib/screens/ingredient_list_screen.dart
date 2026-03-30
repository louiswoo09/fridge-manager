import 'package:flutter/material.dart';
import '../models/ingredient.dart';
import '../services/ingredient_service.dart';

class IngredientListScreen extends StatelessWidget {
  final IngredientService _service = IngredientService();

  IngredientListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('냉장고 매니저')),
      body: StreamBuilder<List<Ingredient>>(
        stream: _service.getIngredients(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('에러 발생: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('등록된 식재료가 없어요.'));
          }

          final items = snapshot.data!;

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];

              final date = item.expirationDate;
              final formattedDate =
                  "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

              return ListTile(
                title: Text('${item.name} (${item.storage})'),
                subtitle: Text('유통기한: $formattedDate'),
                trailing: Text('${item.quantity}${item.unit}', style: TextStyle(fontSize: 20)),
              );
            },
          );
        },
      ),
    );
  }
}