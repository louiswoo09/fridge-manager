import 'package:flutter/material.dart';
import '../services/fridge_service.dart';

class JoinFridgeScreen extends StatefulWidget {
  const JoinFridgeScreen({super.key});

  @override
  State<JoinFridgeScreen> createState() => _JoinFridgeScreenState();
}

class _JoinFridgeScreenState extends State<JoinFridgeScreen> {
  final FridgeService _fridgeService = FridgeService();
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('6자리 코드를 입력해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final fridgeId = await _fridgeService.joinByInviteCode(code);
      
      // 참여한 냉장고로 자동 전환할지 물어봄
      if (!mounted) return;
      final shouldSwitch = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('참여 완료'),
          content: const Text('이 냉장고로 전환할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('나중에'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('전환'),
            ),
          ],
        ),
      );

      if (shouldSwitch == true) {
        await _fridgeService.setActiveFridge(fridgeId);
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final message = e is StateError ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('냉장고 참여')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            const Icon(
              Icons.key,
              size: 64,
              color: Colors.indigo,
            ),
            const SizedBox(height: 16),
            const Text(
              '초대 코드 입력',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '냉장고 소유자에게 받은 6자리 코드를 입력해주세요',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _controller,
              autofocus: true,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 6,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: 'ABC123',
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  letterSpacing: 6,
                ),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onChanged: (value) {
                // 자동으로 대문자 변환
                final upper = value.toUpperCase();
                if (upper != value) {
                  _controller.value = TextEditingValue(
                    text: upper,
                    selection: TextSelection.collapsed(offset: upper.length),
                  );
                }
              },
              onSubmitted: (_) => _join(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _join,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('참여하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}