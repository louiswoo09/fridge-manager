import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../services/fridge_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FridgeDetailScreen extends StatefulWidget {
  final String fridgeId;

  const FridgeDetailScreen({super.key, required this.fridgeId});

  @override
  State<FridgeDetailScreen> createState() => _FridgeDetailScreenState();
}

class _FridgeDetailScreenState extends State<FridgeDetailScreen> {
  final FridgeService _fridgeService = FridgeService();

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;

  Stream<String> _watchMemberName(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) {
          final name = doc.data()?['displayName']?.toString();
          return name?.isNotEmpty == true ? name! : uid.substring(0, 8);
        });
  }

  Future<void> _renameFridge(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('냉장고 이름 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '냉장고 이름'),
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

    if (newName == null ||
        newName.isEmpty ||
        newName == currentName ||
        !mounted) {
      return;
    }

    try {
      await _fridgeService.renameFridge(widget.fridgeId, newName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('이름이 "$newName"으로 변경됨')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('변경 실패: $e')));
    }
  }

  Future<void> _leaveFridge(String name, int memberCount) async {
    final isLast = memberCount <= 1;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('냉장고 떠나기'),
        content: Text(
          isLast
              ? '"$name"의 마지막 멤버입니다.\n떠나면 냉장고와 모든 데이터가 삭제됩니다.\n계속할까요?'
              : '"$name"에서 떠날까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              isLast ? '떠나기 (삭제됨)' : '떠나기',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _fridgeService.leaveFridge(widget.fridgeId);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(isLast ? '냉장고가 삭제됨' : '냉장고에서 떠남')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  Future<void> _kickMember(String targetUid, String targetName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('멤버 강퇴'),
        content: Text('$targetName을(를) 강퇴할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('강퇴', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _fridgeService.kickMember(widget.fridgeId, targetUid);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$targetName 강퇴됨')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  Future<void> _editAlias(String targetUid, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final newAlias = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('호칭 설정'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '호칭',
            hintText: '호칭을 입력하세요',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          if (current != null && current.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('제거', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, controller.text.trim());
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (newAlias == null) return; // 취소

    try {
      await _fridgeService.setMemberAlias(widget.fridgeId, targetUid, newAlias);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newAlias.isEmpty ? '호칭 제거됨' : '호칭 설정됨')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  void _copyInviteCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('초대 코드 복사됨')));
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: const Text('냉장고 관리')),
    body: StreamBuilder<Map<String, dynamic>?>(
      stream: _fridgeService.watchFridge(widget.fridgeId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final fridge = snapshot.data;
        if (fridge == null) {
          return const Center(child: Text('냉장고를 찾을 수 없습니다'));
        }

        return StreamBuilder<Set<String>>(
          stream: _fridgeService.watchPinnedFridges(),
          builder: (context, pinSnap) {
            final isPinned = (pinSnap.data ?? {}).contains(widget.fridgeId);
            return _buildContent(fridge, isPinned);
          },
        );
      },
    ),
  );
}

Widget _buildContent(Map<String, dynamic> fridge, bool isPinned) {
  final name = fridge['name']?.toString() ?? '이름 없음';
  final ownerUid = fridge['ownerUid']?.toString() ?? '';
  final memberUids = List<String>.from(fridge['memberUids'] ?? []);
  final inviteCode = fridge['inviteCode']?.toString() ?? '';
  final isOwner = ownerUid == _myUid;

  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // 냉장고 이름
      Card(
        child: ListTile(
          leading: const Icon(Icons.kitchen, color: Colors.deepPurple),
          title: Text(
            name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text('멤버 ${memberUids.length}명'),
          trailing: IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => _renameFridge(name),
          ),
        ),
      ),

      const SizedBox(height: 16),

      // 초대 코드
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.key, size: 18, color: Colors.indigo),
                  SizedBox(width: 6),
                  Text(
                    '초대 코드',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        inviteCode,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                          fontFamily: 'monospace',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copyInviteCode(inviteCode),
                    tooltip: '복사',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '이 코드를 공유해 다른 사람을 초대할 수 있어요',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),

      const SizedBox(height: 16),

      // 멤버 목록
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.people, size: 18, color: Colors.indigo),
                  SizedBox(width: 6),
                  Text(
                    '멤버',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...memberUids.map((uid) {
                final isMe = uid == _myUid;
                final isOwnerMember = uid == ownerUid;
                final aliases = Map<String, dynamic>.from(
                  fridge['memberAliases'] ?? {},
                );
                final alias = aliases[uid]?.toString();

                return StreamBuilder<String>(
                  stream: _watchMemberName(uid),
                  builder: (context, snap) {
                    final name = snap.data ?? uid.substring(0, 8);

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: isOwnerMember
                            ? Colors.amber.shade100
                            : Colors.grey.shade200,
                        child: Icon(
                          isOwnerMember ? Icons.shield : Icons.person,
                          size: 18,
                          color: isOwnerMember
                              ? Colors.amber.shade800
                              : Colors.grey.shade700,
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          if (alias != null && alias.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                alias,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          if (isOwnerMember) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '방장',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.amber.shade900,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          if (isOwner)
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              tooltip: '호칭 설정',
                              onPressed: () => _editAlias(uid, alias),
                            ),
                          if (isOwner && !isMe)
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              tooltip: '강퇴',
                              onPressed: () => _kickMember(uid, name),
                            ),
                        ],
                      ),
                    );
                  },
                );
              }),
            ],
          ),
        ),
      ),

      const SizedBox(height: 24),

      // 떠나기 (핀이면 비활성)
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: isPinned
              ? null
              : () => _leaveFridge(name, memberUids.length),
          icon: Icon(
            Icons.exit_to_app,
            color: isPinned ? Colors.grey : Colors.red,
          ),
          label: Text(
            isPinned ? '핀 해제 후 떠날 수 있어요' : '냉장고 떠나기',
            style: TextStyle(
              color: isPinned ? Colors.grey : Colors.red,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(
              color: isPinned ? Colors.grey.shade300 : Colors.red,
            ),
          ),
        ),
      ),
    ],
  );
}
}
