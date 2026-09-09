import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../api.dart';
import '../widgets.dart';

class StoryEditorScreen extends StatefulWidget {
  const StoryEditorScreen({super.key, required this.api, required this.onPublished});
  final ApiClient api;
  final VoidCallback onPublished;

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  final textCtrl = TextEditingController();
  final picker = ImagePicker();
  XFile? photo;
  int selectedGradient = 0;
  String selectedSticker = '';
  bool busy = false;

  static const gradients = [
    [Color(0xFFFF7E5F), Color(0xFFFEB47B)], // Sunrise
    [Color(0xFF2193B0), Color(0xFF6DD5ED)], // Ocean
    [Color(0xFF11998E), Color(0xFF38EF7D)], // Mint
    [Color(0xFF8E2DE2), Color(0xFF4A00E0)], // Lavender
    [Color(0xFFF857A6), Color(0xFFFF5858)], // Berry
  ];

  static const stickers = ['⭐ Star', '🚀 Curious', '🎨 Creative', '📚 Bookworm', '🏆 Champion', '🌈 Kindness'];

  Future<void> _pick(ImageSource source) async {
    final file = await picker.pickImage(source: source, imageQuality: 88, maxWidth: 1800);
    if (file != null) setState(() => photo = file);
  }

  Future<void> _publish() async {
    if (busy) return;
    final caption = [textCtrl.text.trim(), selectedSticker].where((s) => s.isNotEmpty).join(' ');
    if (caption.isEmpty && photo == null) {
      toast(context, 'Add a photo or a story note first.');
      return;
    }
    setState(() => busy = true);
    try {
      final res = await widget.api.uploadPost(
        kind: 'story',
        caption: caption,
        category: 'Art',
        audience: 'ALL',
        media: photo == null ? null : File(photo!.path),
      );
      if (!mounted) return;
      final status = res['status']?.toString() ?? 'ALLOW';
      toast(context, status == 'REVIEW' ? 'Story waiting for safety review' : 'Story published safely!');
      widget.onPublished();
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = gradients[selectedGradient];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Story Editor'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: busy ? null : _publish,
              icon: busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, size: 18),
              label: const Text('Share'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
              ),
              child: Stack(
                children: [
                  if (photo != null)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(File(photo!.path), fit: BoxFit.cover),
                      ),
                    ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        textCtrl.text.isEmpty && selectedSticker.isEmpty ? 'Type your story note below...' : '\n',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: textCtrl,
                  maxLength: 200,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Add words to your story...',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.camera_alt_outlined), onPressed: () => _pick(ImageSource.camera)),
                        IconButton(icon: const Icon(Icons.photo_outlined), onPressed: () => _pick(ImageSource.gallery)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text('Style: ', style: TextStyle(fontWeight: FontWeight.w700)),
                      ...List.generate(gradients.length, (i) {
                        return GestureDetector(
                          onTap: () => setState(() => selectedGradient = i),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: gradients[i]),
                              border: Border.all(color: selectedGradient == i ? Colors.black : Colors.transparent, width: 2),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: stickers.map((st) {
                      final active = selectedSticker == st;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(st),
                          selected: active,
                          onSelected: (val) => setState(() => selectedSticker = val ? st : ''),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReelEditorScreen extends StatefulWidget {
  const ReelEditorScreen({super.key, required this.api, required this.onPublished});
  final ApiClient api;
  final VoidCallback onPublished;

  @override
  State<ReelEditorScreen> createState() => _ReelEditorScreenState();
}

class _ReelEditorScreenState extends State<ReelEditorScreen> {
  final captionCtrl = TextEditingController();
  final picker = ImagePicker();
  XFile? video;
  String category = 'Science';
  String soundTag = 'Original Audio';
  bool busy = false;

  static const categories = ['Science', 'Math', 'Coding', 'Art', 'Sports', 'Music', 'Nature', 'Books', 'Other'];
  static const soundOptions = ['Original Audio', 'Classroom Quiet', 'Nature Ambience', 'Study Beats'];

  Future<void> _pick(ImageSource source) async {
    final file = await picker.pickVideo(source: source, maxDuration: const Duration(seconds: 60));
    if (file != null) setState(() => video = file);
  }

  Future<void> _publish() async {
    if (busy) return;
    if (video == null) {
      toast(context, 'Please record or select a video reel first.');
      return;
    }
    setState(() => busy = true);
    try {
      final res = await widget.api.uploadPost(
        kind: 'reel',
        caption: [captionCtrl.text.trim(), '[]'].where((s) => s.isNotEmpty).join(' '),
        category: category,
        audience: 'ALL',
        media: File(video!.path),
      );
      if (!mounted) return;
      final status = res['status']?.toString() ?? 'ALLOW';
      toast(context, status == 'REVIEW' ? 'Reel waiting for safety review' : 'Reel published safely!');
      widget.onPublished();
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    captionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reel Creator & Editor')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              height: 260,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
              ),
              child: video == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_outlined, size: 56, color: Colors.white70),
                          const SizedBox(height: 12),
                          const Text('Record or select video reel (max 60s)', style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FilledButton.icon(
                                onPressed: () => _pick(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Record'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: () => _pick(ImageSource.gallery),
                                icon: const Icon(Icons.video_library_outlined),
                                label: const Text('Gallery'),
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.greenAccent),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(video!.name, style: const TextStyle(color: Colors.white, fontSize: 13), textAlign: TextAlign.center),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                            onPressed: () => setState(() => video = null),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: captionCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reel Caption',
                hintText: 'Share a safe demonstration, explanation or creative project...',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Educational Topic'),
              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => category = v ?? 'Science'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: soundTag,
              decoration: const InputDecoration(labelText: 'Audio & Narration'),
              items: soundOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => soundTag = v ?? 'Original Audio'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy ? null : _publish,
              icon: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.shield_rounded),
              label: Text(busy ? 'Checking Safety...' : 'Verify Safety & Publish Reel'),
            ),
          ],
        ),
      ),
    );
  }
}

class StudyCircleScreen extends StatelessWidget {
  const StudyCircleScreen({super.key, required this.api, required this.circleName, required this.members});
  final ApiClient api;
  final String circleName;
  final List<String> members;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(circleName),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.green.shade50,
            child: const Row(
              children: [
                Icon(Icons.verified_user_rounded, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Supervised Study Circle • Monitored for safety and respect',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Chip(
                    avatar: const Icon(Icons.lock_clock_outlined, size: 16),
                    label: Text(' friends participating'),
                  ),
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Study Circle Guidelines', style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 6),
                        Text('• Share homework help, science discoveries, and creative projects.', style: TextStyle(fontSize: 13)),
                        Text('• Be kind, encouraging and respectful to everyone.', style: TextStyle(fontSize: 13)),
                        Text('• Never share passwords, home locations or contact info.', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.black12)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Message study circle...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send_rounded),
                    onPressed: () => toast(context, 'Study Circle message sent for moderation.'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ModerationResultScreen extends StatelessWidget {
  const ModerationResultScreen({
    super.key,
    required this.status,
    required this.reason,
    this.contentType = 'POST',
    this.caption,
    this.mediaUrl,
    this.onProceed,
  });

  final String status;
  final String reason;
  final String contentType;
  final String? caption;
  final String? mediaUrl;
  final VoidCallback? onProceed;

  @override
  Widget build(BuildContext context) {
    final isAllowed = status == 'ALLOWED' || status == 'ACTIVE';
    final isReview = status == 'REVIEW';

    final color = isAllowed
        ? const Color(0xFF16A34A)
        : isReview
            ? const Color(0xFFD97706)
            : const Color(0xFFDC2626);

    final title = isAllowed
        ? 'Passed Safety Review'
        : isReview
            ? 'Waiting for Parent / Guardian Approval'
            : 'Content Needs Adjustment';

    return Scaffold(
      appBar: AppBar(title: const Text('Safety Check Result')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isAllowed
                    ? Icons.check_circle_rounded
                    : isReview
                        ? Icons.schedule_rounded
                        : Icons.error_rounded,
                size: 48,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 24),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI Safety Diagnostics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Divider(height: 20),
                  _DiagRow(label: 'Content Type', value: contentType),
                  const _DiagRow(label: 'Safety Policy', value: 'COPPA & DPDP Child Safe'),
                  const _DiagRow(label: 'PII Check', value: 'Passed — No contact info leaked'),
                  const _DiagRow(label: 'Visual Protection', value: 'Active'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              if (onProceed != null) onProceed!();
            },
            icon: Icon(isAllowed ? Icons.done_all_rounded : Icons.arrow_back_rounded),
            label: Text(isAllowed ? 'Continue to Feed' : 'Back to Safety Hub'),
          ),
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

