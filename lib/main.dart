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
import 'services/fridge_service.dart';

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
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: FirebaseAuth.instance.currentUser == null
          ? const LoginScreen()
          : const FridgeInitGate(),
    );
  }
}

class FridgeInitGate extends StatefulWidget {
  const FridgeInitGate({super.key});

  @override
  State<FridgeInitGate> createState() => _FridgeInitGateState();
}

class _FridgeInitGateState extends State<FridgeInitGate> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await FridgeService().ensureDisplayName();
      await FridgeService().ensureActiveFridge();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('초기화 실패\n$_error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _ready = false;
                    });
                    _initialize();
                  },
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return const MainScreen();
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
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: '가격 동향'),
        ],
      ),
    );
  }
}
