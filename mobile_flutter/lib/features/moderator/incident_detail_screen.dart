import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';

class IncidentDetailScreen extends StatefulWidget {
  const IncidentDetailScreen({
    super.key,
    required this.authState,
    required this.eventId,
    this.initialEvent,
  });

  final AuthState authState;
  final int eventId;
  final Map<String, dynamic>? initialEvent;

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  final TextEditingController _notesCtrl = TextEditingController();
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  Map<String, dynamic>? _event;
  Map<String, dynamic>? _preview;

  @override
  void initState() {
    super.initState();
    _event = widget.initialEvent;
    _fetchDetail();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient
          .get('/api/mobile/v1/admin/reviews/${widget.eventId}');
      if (res['ok'] == true && mounted) {
        setState(() {
          _event = res['event'] as Map<String, dynamic>?;
          _preview = res['preview'] as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Unable to load incident details.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitDecision(String action) async {
    final notes = _notesCtrl.text.trim();
    setState(() => _isSubmitting = true);

    try {
      final res = await widget.authState.apiClient.postJson(
        '/api/mobile/v1/admin/reviews/${widget.eventId}',
        {
          'action': action,
          if (notes.isNotEmpty) 'notes': notes,
        },
      );

      if (res['ok'] == true && mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'APPROVE'
                  ? 'Incident approved and content allowed.'
                  : action == 'ESCALATE'
                      ? 'Incident escalated to senior review.'
                      : 'Incident confirmed blocked for child safety.',
            ),
            backgroundColor: action == 'APPROVE'
                ? const Color(0xFF2E7D32)
                : const Color(0xFFC62828),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not submit moderation review.'),
            backgroundColor: Color(0xFFC62828),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ev = _event ?? {};
    final childName =
        ev['full_name'] as String? ?? 'Child ID #${ev['child_id'] ?? ''}';
    final username = ev['username'] as String? ?? 'student';
    final contentType = ev['content_type'] as String? ?? 'CONTENT';
    final reason = ev['reason'] as String? ?? 'Pending automated review';
    final riskScore = ev['risk_score'] != null
        ? double.tryParse(ev['risk_score'].toString()) ?? 0.0
        : 0.0;
    final isCritical = riskScore >= 70.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Incident #${widget.eventId}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isCritical
                  ? const Color(0xFFEF4444)
                  : const Color(0xFFF59E0B),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                isCritical ? 'CRITICAL RISK' : 'REVIEW',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading && _event == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _event == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _fetchDetail,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── User Information Card ─────────────────
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: const Color(0xFFE2E8F0),
                                child: Text(
                                  childName.isNotEmpty
                                      ? childName[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      childName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      '@$username · Child Account',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  contentType,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── AI Safety Analysis Card ───────────────
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.security_rounded,
                                      size: 18, color: Color(0xFF2563EB)),
                                  SizedBox(width: 8),
                                  Text(
                                    'AI Safety Analysis',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFFFECACA)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.warning_amber_rounded,
                                        size: 18, color: Color(0xFFDC2626)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        reason,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF991B1B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Calculated Risk Score',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  Text(
                                    '${riskScore.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: isCritical
                                          ? const Color(0xFFDC2626)
                                          : const Color(0xFFD97706),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── Content Preview Card ──────────────────
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Flagged Content Preview',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_preview != null &&
                                  (_preview!['caption'] != null ||
                                      _preview!['comment_text'] != null ||
                                      _preview!['message_text'] != null)) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Text(
                                    _preview!['caption']?.toString() ??
                                        _preview!['comment_text']?.toString() ??
                                        _preview!['message_text']?.toString() ??
                                        '',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF1E293B),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ] else ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Text(
                                    ev['raw_text']?.toString() ??
                                        'Media content or message flagged during moderation audit.',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF475569),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── Moderator Notes ───────────────────────
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Auditor Notes (Optional)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _notesCtrl,
                                maxLines: 2,
                                decoration: InputDecoration(
                                  hintText:
                                      'Add rationale for approval or policy enforcement...',
                                  hintStyle: const TextStyle(
                                      fontSize: 13, color: Color(0xFF94A3B8)),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  contentPadding: const EdgeInsets.all(12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Action Buttons ────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _submitDecision('APPROVE'),
                              icon: const Icon(Icons.check_circle_outline,
                                  size: 18),
                              label: const Text('Approve Content'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _submitDecision('BLOCK'),
                              icon: const Icon(Icons.block_rounded, size: 18),
                              label: const Text('Enforce Block'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFEF4444),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isSubmitting
                            ? null
                            : () => _submitDecision('ESCALATE'),
                        icon: const Icon(Icons.flag_outlined, size: 16),
                        label: const Text('Escalate to Senior Safety Team'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF64748B),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}
