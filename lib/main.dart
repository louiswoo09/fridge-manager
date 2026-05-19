import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/ingredient_list_screen.dart';
import 'screens/recipe_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/login_screen.dart';
import 'services/notification_service.dart';
import 'screens/shopping_screen.dart';
import 'models/recipe_mode.dart';

typedef OnRequestRecipeKeywordSearch = void Function(List<String> keywords);
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '냉장고 매니저',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: FirebaseAuth.instance.currentUser == null
          ? const LoginScreen()
          : const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final GlobalKey<RecipeScreenState> _recipeKey =
      GlobalKey<RecipeScreenState>();

  void _switchToRecipeWithMode(RecipeMode mode) {
    _recipeKey.currentState?.setMode(mode);
    setState(() => _currentIndex = 1);
  }

  void _switchToRecipeKeywordSearch(List<String> keywords) {
    setState(() => _currentIndex = 1);
    _recipeKey.currentState?.searchByMultipleKeywords(keywords);
  }

  late final List<Widget> _screens = [
    IngredientListScreen(
      onRequestRecipeKeywordSearch: _switchToRecipeKeywordSearch,
    ),
    RecipeScreen(key: _recipeKey),
    ShoppingScreen(onRequestRecipe: _switchToRecipeWithMode),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.kitchen), label: '냉장고'),
          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu),
            label: '레시피 추천',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: '가격 동향',
          ),
        ],
      ),
    );
  }
}
