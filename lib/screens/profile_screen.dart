import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/fridge_service.dart';
import 'login_screen.dart';
import 'fridge_detail_screen.dart';
import 'join_fridge_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FridgeService _fridgeService = FridgeService();

  Future<void> _signOut(BuildContext context) async {
    await GoogleSignIn.instance.disconnect();
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _createFridge() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 냉장고'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '냉장고 이름',
            hintText: '예: 우리집 냉장고',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('만들기'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || !mounted) return;

    try {
      await _fridgeService.createFridge(name);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$name 생성됨')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('생성 실패: $e')));
    }
  }

  Future<void> _switchFridge(String fridgeId, String fridgeName) async {
    try {
      await _fridgeService.setActiveFridge(fridgeId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$fridgeName"으로 전환됨')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('전환 실패: $e')));
    }
  }

  Future<void> _editDisplayName(String current) async {
    final controller = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이름 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '이름'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('변경'),
          ),
        ],
      ),
    );

    if (newName == null || newName == current) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .set({'displayName': newName}, SetOptions(merge: true));
  }

  Widget _buildFridgeCard({
    required String id,
    required String name,
    required int memberCount,
    required bool isActive,
    required bool isOwner,
    required bool isPinned,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isActive ? Colors.deepPurple.shade50 : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? Colors.deepPurple : Colors.grey.shade300,
          child: Icon(
            Icons.kitchen,
            color: isActive ? Colors.white : Colors.grey,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.deepPurple : Colors.black87,
                ),
              ),
            ),
            if (isPinned) ...[
              const SizedBox(width: 4),
              Icon(Icons.push_pin, size: 14, color: Colors.deepPurple.shade400),
            ],
            if (isActive) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '활성',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            if (isOwner) ...[
              const SizedBox(width: 4),
              Icon(Icons.shield, size: 14, color: Colors.amber.shade700),
            ],
          ],
        ),
        subtitle: Text(
          '멤버 $memberCount명',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (action) {
            if (action == 'switch') {
              _switchFridge(id, name);
            } else if (action == 'pin') {
              _togglePin(id, name, isPinned);
            } else if (action == 'detail') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FridgeDetailScreen(fridgeId: id),
                ),
              );
            }
          },
          itemBuilder: (context) => [
            if (!isActive)
              const PopupMenuItem(
                value: 'switch',
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz, size: 18),
                    SizedBox(width: 8),
                    Text('이 냉장고 사용'),
                  ],
                ),
              ),
            PopupMenuItem(
              value: 'pin',
              child: Row(
                children: [
                  Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(isPinned ? '핀 해제' : '핀 고정'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'detail',
              child: Row(
                children: [
                  Icon(Icons.settings, size: 18),
                  SizedBox(width: 8),
                  Text('관리'),
                ],
              ),
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FridgeDetailScreen(fridgeId: id)),
          );
        },
      ),
    );
  }

  Future<void> _togglePin(
    String fridgeId,
    String name,
    bool currentPinned,
  ) async {
    try {
      await _fridgeService.togglePin(fridgeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(currentPinned ? '$name 핀 해제' : '$name 핀 고정'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('프로필')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            CircleAvatar(
              radius: 48,
              backgroundImage: user?.photoURL != null
                  ? NetworkImage(user!.photoURL!)
                  : null,
              child: user?.photoURL == null
                  ? const Icon(Icons.person, size: 48)
                  : null,
            ),
            const SizedBox(height: 16),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser?.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final name =
                    snapshot.data?.data()?['displayName']?.toString() ??
                    user?.displayName ??
                    '이름 없음';
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () => _editDisplayName(name),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              user?.email ?? '이메일 없음',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),

            // 냉장고 섹션
            _buildFridgeSection(),

            const SizedBox(height: 32),

            // 로그아웃 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _signOut(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('로그아웃'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildFridgeSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const Icon(Icons.kitchen, size: 18, color: Colors.deepPurple),
                const SizedBox(width: 6),
                const Text(
                  '내 냉장고',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const JoinFridgeScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.input, size: 16),
                  label: const Text('코드로 참여'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _fridgeService.watchMyFridges(),
            builder: (context, fridgeSnap) {
              if (fridgeSnap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final fridges = fridgeSnap.data ?? [];

              return StreamBuilder<String?>(
                stream: _fridgeService.watchActiveFridgeId(),
                builder: (context, activeSnap) {
                  final activeId = activeSnap.data;

                  return StreamBuilder<Set<String>>(
                    stream: _fridgeService.watchPinnedFridges(),
                    builder: (context, pinSnap) {
                      final pinnedIds = pinSnap.data ?? <String>{};

                      // 핀 우선 정렬
                      final sortedFridges = [...fridges]
                        ..sort((a, b) {
                          final aId = a['_id']?.toString() ?? '';
                          final bId = b['_id']?.toString() ?? '';
                          final aPinned = pinnedIds.contains(aId);
                          final bPinned = pinnedIds.contains(bId);
                          if (aPinned && !bPinned) return -1;
                          if (!aPinned && bPinned) return 1;
                          return 0; // 같은 그룹이면 원래 순서 유지
                        });

                      return Column(
                        children: [
                          ...sortedFridges.map((fridge) {
                            final id = fridge['_id']?.toString() ?? '';
                            final name = fridge['name']?.toString() ?? '이름 없음';
                            final memberCount =
                                (fridge['memberUids'] as List?)?.length ?? 1;
                            final isActive = id == activeId;
                            final isOwner =
                                fridge['ownerUid'] ==
                                FirebaseAuth.instance.currentUser?.uid;
                            final isPinned = pinnedIds.contains(id);

                            return _buildFridgeCard(
                              id: id,
                              name: name,
                              memberCount: memberCount,
                              isActive: isActive,
                              isOwner: isOwner,
                              isPinned: isPinned,
                            );
                          }),

                          // 새 냉장고 만들기 버튼
                          Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.grey,
                                child: Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: const Text(
                                '새 냉장고 만들기',
                                style: TextStyle(color: Colors.grey),
                              ),
                              onTap: _createFridge,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
