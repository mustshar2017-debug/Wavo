import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

const supabaseUrl = 'https://jajaujilwhkroboyhenj.supabase.co';
const supabasePublishableKey = 'sb_publishable_9-FF377xk93I2f3XhWN-3w_UkxdOZLR';
const videoBucket = 'videos';

const Color wavoBg = Color(0xFF080B0E);
const Color wavoPanel = Color(0xFF151B20);
const Color wavoAccent = Color(0xFF55E6C1);
const Color wavoPink = Color(0xFFFF5278);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabasePublishableKey,
  );
  runApp(const WavoApp());
}

final supabase = Supabase.instance.client;

class WavoApp extends StatelessWidget {
  const WavoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WAVO – وافي العالمي',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: wavoBg,
        colorScheme: const ColorScheme.dark(
          primary: wavoAccent,
          surface: wavoPanel,
          secondary: wavoPink,
        ),
        fontFamily: 'Arial',
        useMaterial3: true,
      ),
      home: const WavoHome(),
    );
  }
}

class WavoVideo {
  const WavoVideo({required this.name, required this.url});
  final String name;
  final String url;
}

class WavoHome extends StatefulWidget {
  const WavoHome({super.key});

  @override
  State<WavoHome> createState() => _WavoHomeState();
}

class _WavoHomeState extends State<WavoHome> {
  final _picker = ImagePicker();
  List<WavoVideo> _videos = [];
  bool _loading = true;
  bool _uploading = false;
  int _tab = 0;
  int _activeVideo = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final files = await supabase.storage.from(videoBucket).list(
        path: '',
        searchOptions: const SearchOptions(limit: 100),
      );
      const extensions = ['.mp4', '.mov', '.m4v', '.webm', '.ogg'];
      final items = files
          .where((file) => extensions.any(
                (ext) => file.name.toLowerCase().endsWith(ext),
              ))
          .map((file) => WavoVideo(
                name: file.name,
                url: supabase.storage.from(videoBucket).getPublicUrl(file.name),
              ))
          .toList();
      if (!mounted) return;
      setState(() {
        _videos = items;
        _loading = false;
        if (items.isEmpty) _message = 'لا توجد فيديوهات منشورة حالياً.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'تعذر تحميل الفيديوهات: $error';
      });
    }
  }

  Future<void> _pickAndUploadVideo() async {
    if (supabase.auth.currentUser == null) {
      _showAuth();
      return;
    }
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.length > 100 * 1024 * 1024) {
        throw Exception('الحد الأقصى لحجم الفيديو 100 ميجابايت.');
      }
      final safeName = file.name.replaceAll(RegExp(r'[^\p{L}\p{N}._-]', unicode: true), '_');
      final path = '${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final contentType = file.name.toLowerCase().endsWith('.mov')
          ? 'video/quicktime'
          : 'video/mp4';
      await supabase.storage.from(videoBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: false,
            ),
          );
      await _loadVideos();
      if (mounted) _notice('تم رفع الفيديو بنجاح.');
    } catch (error) {
      if (mounted) _notice('تعذر رفع الفيديو: $error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: wavoPanel),
    );
  }

  Future<void> _showAuth() async {
    final email = TextEditingController();
    final password = TextEditingController();
    final name = TextEditingController();
    bool createAccount = false;
    bool busy = false;
    String? errorText;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: wavoPanel,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> submit() async {
            setSheetState(() {
              busy = true;
              errorText = null;
            });
            try {
              if (createAccount) {
                await supabase.auth.signUp(
                  email: email.text.trim(),
                  password: password.text,
                  data: {'full_name': name.text.trim()},
                );
              } else {
                await supabase.auth.signInWithPassword(
                  email: email.text.trim(),
                  password: password.text,
                );
              }
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              if (mounted) setState(() {});
              _notice(createAccount
                  ? 'تم إرسال طلب إنشاء الحساب. تحقق من بريدك إذا طُلب ذلك.'
                  : 'تم تسجيل الدخول.');
            } catch (e) {
              setSheetState(() => errorText = e.toString());
            } finally {
              if (sheetContext.mounted) setSheetState(() => busy = false);
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    createAccount ? 'إنشاء حساب WAVO' : 'تسجيل الدخول',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: wavoAccent, fontSize: 22, fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (createAccount) _field(name, 'الاسم الظاهر'),
                  _field(email, 'البريد الإلكتروني', keyboard: TextInputType.emailAddress),
                  _field(password, 'كلمة المرور', obscure: true),
                  if (errorText != null)
                    Text(errorText!, style: const TextStyle(color: wavoPink)),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? 'يرجى الانتظار...' : (createAccount ? 'إنشاء الحساب' : 'دخول')),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setSheetState(() {
                              createAccount = !createAccount;
                              errorText = null;
                            }),
                    child: Text(createAccount
                        ? 'لديك حساب؟ سجّل الدخول'
                        : 'مستخدم جديد؟ أنشئ حساباً'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: wavoBg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (mounted) setState(() {});
    _notice('تم تسجيل الخروج.');
  }

  Widget _buildFeed() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: wavoAccent));
    }
    if (_videos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_circle_outline, color: wavoAccent, size: 64),
              const SizedBox(height: 12),
              Text(_message ?? 'ابدأ رحلتك مع WAVO'),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _loadVideos,
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث'),
              ),
            ],
          ),
        ),
      );
    }
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: _videos.length,
      onPageChanged: (index) => setState(() => _activeVideo = index),
      itemBuilder: (context, index) => WavoVideoCard(
        key: ValueKey(_videos[index].url),
        video: _videos[index],
        active: index == _activeVideo && _tab == 0,
      ),
    );
  }

  Widget _simplePage(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: wavoAccent, size: 58),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.6)),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile() {
    final user = supabase.auth.currentUser;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 42,
              backgroundColor: wavoPanel,
              child: Icon(Icons.person, color: wavoAccent, size: 44),
            ),
            const SizedBox(height: 14),
            Text(user?.email ?? 'مرحباً بك في WAVO',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            if (user == null)
              FilledButton.icon(
                onPressed: _showAuth,
                icon: const Icon(Icons.login),
                label: const Text('تسجيل الدخول / إنشاء حساب'),
              )
            else
              OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('تسجيل الخروج'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: wavoBg,
                child: Row(
                  children: [
                    const Text('WAVO',
                        style: TextStyle(
                          color: wavoAccent, fontSize: 25, fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        )),
                    const Spacer(),
                    IconButton(
                      tooltip: 'تحديث الفيديوهات',
                      onPressed: _loadVideos,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: user == null ? 'تسجيل الدخول' : 'حسابي',
                      onPressed: _showAuth,
                      icon: Icon(user == null ? Icons.login : Icons.account_circle_outlined),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _buildFeed(),
                    _simplePage(Icons.people_outline, 'الأصدقاء', 'سيتم ربط الأصدقاء والمتابعة بحسابك في المرحلة التالية.'),
                    _simplePage(Icons.add_circle_outline, 'نشر فيديو', 'استخدم زر الإضافة أسفل الشاشة لاختيار فيديو من الاستديو.'),
                    _simplePage(Icons.mail_outline, 'صندوق الوارد', 'سيتم ربط الرسائل والإشعارات في المرحلة التالية.'),
                    _buildProfile(),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: wavoPanel,
          indicatorColor: wavoAccent.withValues(alpha: .15),
          selectedIndex: _tab,
          onDestinationSelected: (value) {
            if (value == 2) {
              _pickAndUploadVideo();
            } else {
              setState(() => _tab = value);
              if (value == 4 && supabase.auth.currentUser == null) _showAuth();
            }
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.people_outline), label: 'الأصدقاء'),
            NavigationDestination(icon: Icon(Icons.add_circle, size: 30), label: 'نشر'),
            NavigationDestination(icon: Icon(Icons.mail_outline), label: 'الوارد'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'حسابي'),
          ],
        ),
      ),
    );
  }
}

class WavoVideoCard extends StatefulWidget {
  const WavoVideoCard({
    super.key,
    required this.video,
    required this.active,
  });

  final WavoVideo video;
  final bool active;

  @override
  State<WavoVideoCard> createState() => _WavoVideoCardState();
}

class _WavoVideoCardState extends State<WavoVideoCard> {
  VideoPlayerController? _controller;
  bool _pausedByUser = false;
  bool _showPause = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.video.url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) return;
      setState(() {});
      if (widget.active) controller.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant WavoVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active && !_pausedByUser) {
        _controller?.play();
      } else {
        _controller?.pause();
      }
    }
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      _pausedByUser = controller.value.isPlaying;
      _showPause = _pausedByUser;
    });
    if (_pausedByUser) {
      controller.pause();
    } else {
      controller.play();
    }
    if (_showPause) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _showPause = false);
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlayback,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (_failed)
            const Center(child: Text('تعذر تشغيل هذا الفيديو'))
          else if (controller == null || !controller.value.isInitialized)
            const Center(child: CircularProgressIndicator(color: wavoAccent))
          else
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          const Positioned(
            right: 16,
            bottom: 26,
            child: Text(
              'WAVO WORLD',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
            ),
          ),
          if (_showPause)
            const Center(
              child: CircleAvatar(
                radius: 38,
                backgroundColor: Color(0x99000000),
                child: Icon(Icons.pause, color: Colors.white, size: 44),
              ),
            ),
          if (controller != null && controller.value.isInitialized)
            Positioned(
              bottom: 28,
              left: 16,
              child: Text(
                _pausedByUser ? 'متوقف مؤقتاً' : '♫ الصوت الأصلي',
                style: const TextStyle(color: Colors.white70, shadows: [
                  Shadow(color: Colors.black, blurRadius: 5),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
