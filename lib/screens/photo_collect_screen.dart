import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/ingredient_recognition_service.dart';
import 'package:flutter/services.dart';

import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';

/// 앱 안 카메라로 식재료·영수증 사진을 최대 5장까지 모으는 화면
/// "N장 인식하기" → `Navigator.pop(context, List<XFile>)`
class PhotoCollectScreen extends StatefulWidget {
  const PhotoCollectScreen({super.key});

  @override
  State<PhotoCollectScreen> createState() => _PhotoCollectScreenState();
}

class _PhotoCollectScreenState extends State<PhotoCollectScreen>
    with WidgetsBindingObserver {
  static const int _maxPhotos = 5;

  final List<XFile> _photos = [];
  CameraController? _controller;
  bool _isInitializing = true;
  bool _isTaking = false;
  String? _cameraError;
  bool _initRunning = false;
  bool _isPicking = false;
  StreamSubscription<AccelerometerEvent>? _tiltSub;
  double _iconTurns = 0; // 0: 세로, 0.25 / -0.25: 가로

  int get _remaining => _maxPhotos - _photos.length;
  bool get _isFull => _remaining <= 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initCamera();
    _tiltSub =
        accelerometerEventStream(
          samplingPeriod: SensorInterval.uiInterval,
        ).listen((e) {
          // 폰을 평평하게 눕혔을 땐 방향을 판단할 수 없으니 그대로 둠
          if (e.x.abs() < 4 && e.y.abs() < 4) return;
          final turns = e.x.abs() > e.y.abs() ? (e.x > 0 ? 0.25 : -0.25) : 0.0;
          if (turns != _iconTurns && mounted) {
            setState(() => _iconTurns = turns);
          }
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
    _tiltSub?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      final controller = _controller;
      if (mounted) setState(() => _controller = null);
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        !_initRunning) {
      setState(() {
        _isInitializing = true;
        _cameraError = null;
      });
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_initRunning) return;
    _initRunning = true;
    CameraController? controller;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('NoCamera', '카메라 없음');

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = controller;
      await controller.initialize();

      if (!mounted || _controller != controller) return;
      setState(() => _isInitializing = false);
    } on CameraException catch (e) {
      debugPrint('카메라 초기화 실패: ${e.code} ${e.description}');
      // 이미 다른 카메라로 바뀌었거나 정리된 경우엔 에러를 띄우지 않음
      if (!mounted || (controller != null && _controller != controller)) return;
      final denied = e.code.startsWith('CameraAccess');
      setState(() {
        _isInitializing = false;
        _cameraError = denied
            ? '카메라 권한이 필요해요.\n설정에서 카메라 권한을 허용하거나\n앨범에서 사진을 골라주세요.'
            : '카메라를 열 수 없어요.\n앨범에서 사진을 골라주세요.';
      });
    } catch (e) {
      debugPrint('카메라 초기화 실패: $e');
      if (!mounted || (controller != null && _controller != controller)) return;
      setState(() {
        _isInitializing = false;
        _cameraError = '카메라를 열 수 없어요.\n앨범에서 사진을 골라주세요.';
      });
    } finally {
      _initRunning = false;
      // 켜지는 도중 화면을 벗어났다가 돌아온 경우 → 다시 켜기
      if (mounted &&
          _controller == null &&
          _cameraError == null &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _initCamera();
      }
    }
  }

  void _showFullNotice() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('사진은 최대 5장까지 담을 수 있어요'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isTaking ||
        _isFull) {
      return;
    }

    setState(() => _isTaking = true);
    try {
      final file = await controller.takePicture().timeout(
        const Duration(seconds: 5),
      );
      if (!mounted) return;
      setState(() => _photos.add(file));
    } catch (e) {
      debugPrint('촬영 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('사진을 찍지 못했어요')));
    } finally {
      if (mounted) setState(() => _isTaking = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isPicking) return; // 앨범이 열리는 중이면 무시
    final remaining = _remaining;
    if (remaining <= 0) return;

    setState(() => _isPicking = true);
    try {
      final files = await IngredientRecognitionService.pickMultiImage(
        limit: remaining,
      );
      if (!mounted || files.isEmpty) return;

      final accepted = files.take(remaining).toList();
      setState(() => _photos.addAll(accepted));

      if (files.length > remaining) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '최대 $_maxPhotos장까지 담을 수 있어서 ${accepted.length}장만 추가했어요',
            ),
          ),
        );
      }
    } on PlatformException catch (e) {
      // 혹시 다른 경로로 두 번 열리려 해도 앱이 멈추지 않게
      debugPrint('앨범 열기 실패: ${e.code}');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  // ───────── 화면 ─────────

  Widget _buildPreview() {
    final controller = _controller;

    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _cameraError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, height: 1.5),
          ),
        ),
      );
    }

    if (_isInitializing ||
        controller == null ||
        !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // 미리보기를 화면에 꽉 차게 (찌그러지지 않게 잘라서)
    final size = controller.value.previewSize;
    if (size == null) return CameraPreview(controller);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height, // 센서 기준 가로·세로가 반대라서 뒤집음
          height: size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildThumbnail(int index) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _rotating(
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_photos[index].path),
                    fit: BoxFit.cover,
                    cacheWidth: 160,
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: InkWell(
                  onTap: () => setState(() => _photos.removeAt(index)),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rotating(Widget child) => AnimatedRotation(
    turns: _iconTurns,
    duration: const Duration(milliseconds: 200),
    child: child,
  );

  Widget _buildShutter() {
    final enabled =
        _controller?.value.isInitialized == true &&
        !_isTaking &&
        !_isFull &&
        _cameraError == null;

    return GestureDetector(
      onTap: _isFull ? _showFullNotice : (enabled ? _takePhoto : null),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        padding: const EdgeInsets.all(4),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? Colors.white : Colors.white24,
          ),
          child: _isTaking
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPreview()),

          // 위: 닫기 + 안내 + 장수
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  _rotating(
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      '식재료나 영수증을 찍어주세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                  _rotating(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_photos.length}/$_maxPhotos',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),

          // 아래: 찍은 사진 줄 + 앨범·셔터 + 인식 버튼
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black54,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_photos.isNotEmpty)
                        SizedBox(
                          height: 64,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _photos.length,
                            itemBuilder: (_, i) => _buildThumbnail(i),
                          ),
                        ),
                      if (_photos.isNotEmpty) const SizedBox(height: 12),
                      Row(
                        children: [
                          // 앨범
                          SizedBox(
                            width: 56,
                            child: IconButton(
                              icon: Icon(
                                Icons.photo_library,
                                color: _isFull ? Colors.white38 : Colors.white,
                                size: 28,
                              ),
                              tooltip: '앨범에서 선택',
                              onPressed: _isPicking
                                  ? null
                                  : (_isFull
                                        ? _showFullNotice
                                        : _pickFromGallery),
                            ),
                          ),
                          const Spacer(),
                          _buildShutter(),
                          const Spacer(),
                          const SizedBox(width: 56), // 셔터를 가운데 두기 위한 자리
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: _photos.isEmpty
                            ? null
                            : ElevatedButton(
                                onPressed: () => Navigator.pop(
                                  context,
                                  List<XFile>.of(_photos),
                                ),
                                child: Text('${_photos.length}장 인식하기'),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
