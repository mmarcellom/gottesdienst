import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';

/// Tertius Streaming-Migration — interaktiver Plan
///
/// Lebt-Doku: Notizen pro Sektion + Checklisten werden lokal persistiert
/// (SharedPreferences). Jeder, der die Doku liest, kann unten ergänzen.
class MigrationPlanScreen extends StatefulWidget {
  const MigrationPlanScreen({super.key});

  @override
  State<MigrationPlanScreen> createState() => _MigrationPlanScreenState();
}

class _MigrationPlanScreenState extends State<MigrationPlanScreen>
    with SingleTickerProviderStateMixin {
  static const _checksKey = 'tertius_migration_checks_v1';
  static const _notesKey = 'tertius_migration_notes_v1';

  Map<String, bool> _checks = {};
  Map<String, String> _notes = {};
  final Map<String, TextEditingController> _noteCtrls = {};
  final Set<String> _collapsed = {};
  late AnimationController _fadeIn;

  @override
  void initState() {
    super.initState();
    _fadeIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _load();
  }

  @override
  void dispose() {
    _fadeIn.dispose();
    for (final c in _noteCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawChecks = prefs.getString(_checksKey);
    if (rawChecks != null) {
      _checks = (jsonDecode(rawChecks) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as bool));
    }
    final rawNotes = prefs.getString(_notesKey);
    if (rawNotes != null) {
      _notes = (jsonDecode(rawNotes) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String));
    }
    setState(() {});
    _fadeIn.forward();
  }

  Future<void> _saveChecks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_checksKey, jsonEncode(_checks));
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notesKey, jsonEncode(_notes));
  }

  void _toggleCheck(String id) {
    setState(() => _checks[id] = !(_checks[id] ?? false));
    _saveChecks();
  }

  void _toggleSection(String id) {
    setState(() {
      _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id);
    });
  }

  TextEditingController _ctrlFor(String id) {
    return _noteCtrls.putIfAbsent(
      id,
      () => TextEditingController(text: _notes[id] ?? ''),
    );
  }

  int get _totalChecks =>
      _sections.fold(0, (s, sec) => s + sec.checks.length);
  int get _doneChecks => _sections.fold(
        0,
        (s, sec) =>
            s + sec.checks.where((c) => _checks[c.id] == true).length,
      );

  @override
  Widget build(BuildContext context) {
    final pct = _totalChecks > 0 ? (_doneChecks / _totalChecks * 100).round() : 0;

    return Scaffold(
      backgroundColor: TertiusTheme.bg,
      body: FadeTransition(
        opacity: _fadeIn,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: TertiusTheme.bg,
              pinned: true,
              expandedHeight: 140,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new,
                    size: 18, color: Colors.white.withOpacity(0.8)),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding:
                    const EdgeInsets.only(left: 56, bottom: 16, right: 16),
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Migration',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: TertiusTheme.text,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F7CFF).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF4F7CFF).withOpacity(0.3)),
                      ),
                      child: Text(
                        '$pct%',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF4F7CFF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Hero info card
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: TertiusTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _totalChecks > 0
                            ? _doneChecks / _totalChecks
                            : 0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF4F7CFF),
                                Color(0xFF7C4FFF),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$_doneChecks / $_totalChecks Checks abgehakt',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.35),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _heroCard(),
                    const SizedBox(height: 12),
                    _statRow(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Sections
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final sec = _sections[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildSectionCard(sec),
                    );
                  },
                  childCount: _sections.length,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  // ─── Hero ─────────────────────────────────────────────────────────────────
  Widget _heroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF4F7CFF).withOpacity(0.12),
            const Color(0xFF7C4FFF).withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFF4F7CFF).withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('STAND 2026-04-07',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.7),
                      letterSpacing: 0.6,
                    )),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: TertiusTheme.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: TertiusTheme.green.withOpacity(0.3)),
                ),
                child: Text('RISIKO NIEDRIG',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: TertiusTheme.green,
                      letterSpacing: 0.6,
                    )),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Streaming-Setup Migration',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: TertiusTheme.text,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Vom 5-Geräte-Setup zur Ein-Knopf-Bedienung',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Aufbauzeit halbieren, Bedienung auf eine Person reduzieren, '
            'Aushilfen-tauglich machen. Altes Setup bleibt 4 Wochen als Backup.',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.white.withOpacity(0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow() {
    return Row(
      children: [
        _statBox('~28 min', 'weniger Aufbau', TertiusTheme.green),
        const SizedBox(width: 8),
        _statBox('2', 'statt 5 Geräte', const Color(0xFF4F7CFF)),
        const SizedBox(width: 8),
        _statBox('~1.200 €', 'Verkaufserlös', const Color(0xFFF59E0B)),
      ],
    );
  }

  Widget _statBox(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: -0.3,
                )),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.55),
                )),
          ],
        ),
      ),
    );
  }

  // ─── Section Card ─────────────────────────────────────────────────────────
  Widget _buildSectionCard(_Section sec) {
    final collapsed = _collapsed.contains(sec.id);
    final done =
        sec.checks.where((c) => _checks[c.id] == true).length;
    final total = sec.checks.length;
    final allDone = total > 0 && done == total;
    final hasNote = (_notes[sec.id] ?? '').trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: TertiusTheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allDone
              ? TertiusTheme.green.withOpacity(0.3)
              : TertiusTheme.border.withOpacity(0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _toggleSection(sec.id),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: TertiusTheme.surface2.withOpacity(0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: sec.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(sec.icon,
                        style: TextStyle(
                          fontSize: 16,
                          color: sec.color,
                        )),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sec.title,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: TertiusTheme.text,
                              letterSpacing: -0.2,
                            )),
                        const SizedBox(height: 2),
                        Text(sec.subtitle,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withOpacity(0.45),
                            )),
                      ],
                    ),
                  ),
                  if (hasNote) ...[
                    Icon(Icons.sticky_note_2_outlined,
                        size: 14,
                        color: const Color(0xFFF5C518).withOpacity(0.7)),
                    const SizedBox(width: 6),
                  ],
                  if (total > 0) ...[
                    Text('$done/$total',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: allDone
                              ? TertiusTheme.green.withOpacity(0.7)
                              : Colors.white.withOpacity(0.4),
                          fontWeight: FontWeight.w500,
                        )),
                    const SizedBox(width: 8),
                  ],
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(Icons.expand_more,
                        size: 18,
                        color: Colors.white.withOpacity(0.35)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: collapsed
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...sec.body.map((b) => _buildBlock(b, sec.color)),
                  if (sec.checks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...sec.checks.map((c) => _buildCheckRow(c)),
                  ],
                  const SizedBox(height: 12),
                  _buildNoteField(sec.id),
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildBlock(_Block b, Color sectionColor) {
    switch (b.kind) {
      case _BlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            b.text!,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.55,
              fontWeight: FontWeight.w400,
              color: Colors.white.withOpacity(0.78),
            ),
          ),
        );
      case _BlockKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(
            b.text!,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: TertiusTheme.text,
              letterSpacing: 0.1,
            ),
          ),
        );
      case _BlockKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 7, right: 10),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: sectionColor.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  b.text!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.55,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withOpacity(0.75),
                  ),
                ),
              ),
            ],
          ),
        );
      case _BlockKind.callout:
        return Container(
          margin: const EdgeInsets.only(bottom: 10, top: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (b.color ?? sectionColor).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: (b.color ?? sectionColor).withOpacity(0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.icon ?? '★',
                  style: TextStyle(
                    fontSize: 14,
                    color: b.color ?? sectionColor,
                  )),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  b.text!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
              ),
            ],
          ),
        );
      case _BlockKind.kv:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: TertiusTheme.border.withOpacity(0.4)),
            ),
            child: Column(
              children: b.rows!.asMap().entries.map((e) {
                final last = e.key == b.rows!.length - 1;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: last
                              ? Colors.transparent
                              : TertiusTheme.border.withOpacity(0.25)),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          e.value[0],
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: sectionColor.withOpacity(0.85),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.value[1],
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            height: 1.5,
                            color: Colors.white.withOpacity(0.75),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
    }
  }

  Widget _buildCheckRow(_Check c) {
    final done = _checks[c.id] == true;
    return GestureDetector(
      onTap: () => _toggleCheck(c.id),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: done ? TertiusTheme.green : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: done ? TertiusTheme.green : TertiusTheme.border,
                  width: 1.5,
                ),
              ),
              child: done
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                c.text,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                  color: done
                      ? Colors.white.withOpacity(0.35)
                      : Colors.white.withOpacity(0.78),
                  decoration:
                      done ? TextDecoration.lineThrough : null,
                  decorationColor: Colors.white.withOpacity(0.25),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteField(String sectionId) {
    final ctrl = _ctrlFor(sectionId);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1419),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFFF5C518).withOpacity(0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sticky_note_2_outlined,
                  size: 12,
                  color: const Color(0xFFF5C518).withOpacity(0.8)),
              const SizedBox(width: 6),
              Text(
                'NOTIZ',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFF5C518).withOpacity(0.8),
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          TextField(
            controller: ctrl,
            maxLines: null,
            minLines: 1,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.5,
              color: TertiusTheme.text,
              fontWeight: FontWeight.w400,
            ),
            cursorColor: const Color(0xFFF5C518),
            decoration: InputDecoration(
              isCollapsed: true,
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText:
                  'Ergänzungen, Fragen, Beobachtungen, Adressen…',
              hintStyle: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withOpacity(0.45),
                fontWeight: FontWeight.w400,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
            ),
            onChanged: (v) {
              _notes[sectionId] = v;
              _saveNotes();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════

enum _BlockKind { paragraph, heading, bullet, callout, kv }

class _Block {
  final _BlockKind kind;
  final String? text;
  final String? icon;
  final Color? color;
  final List<List<String>>? rows;
  const _Block.paragraph(this.text)
      : kind = _BlockKind.paragraph,
        icon = null,
        color = null,
        rows = null;
  const _Block.heading(this.text)
      : kind = _BlockKind.heading,
        icon = null,
        color = null,
        rows = null;
  const _Block.bullet(this.text)
      : kind = _BlockKind.bullet,
        icon = null,
        color = null,
        rows = null;
  const _Block.callout(this.text, {this.icon, this.color})
      : kind = _BlockKind.callout,
        rows = null;
  const _Block.kv(this.rows)
      : kind = _BlockKind.kv,
        text = null,
        icon = null,
        color = null;
}

class _Check {
  final String id;
  final String text;
  const _Check(this.id, this.text);
}

class _Section {
  final String id;
  final String icon;
  final String title;
  final String subtitle;
  final Color color;
  final List<_Block> body;
  final List<_Check> checks;
  const _Section({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.body = const [],
    this.checks = const [],
  });
}

const _blue = Color(0xFF4F7CFF);
const _purple = Color(0xFF7C4FFF);
const _green = Color(0xFF52C07A);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFE05252);

const _sections = <_Section>[
  // 0 — Glossar
  _Section(
    id: 's0',
    icon: '?',
    title: 'Mini-Glossar für Nicht-Techniker',
    subtitle: 'Damit alle dieselbe Sprache sprechen',
    color: _purple,
    body: [
      _Block.kv([
        ['Switch', 'Kleines Kästchen mit mehreren LAN-Buchsen — wie eine Steckdosenleiste, nur für Netzwerkkabel. Haben wir bereits im Saal.'],
        ['RJ45 / LAN', 'Ein normales Netzwerkkabel (sieht aus wie ein dickeres Telefonkabel).'],
        ['RTSP', 'Eine technische Sprache, mit der Kameras ihr Live-Bild übers Netzwerk verschicken.'],
        ['OBS', 'Kostenlose Software auf dem Mac Mini, die Bild + Ton zusammenbaut und zu YouTube schickt. Die neue Stream-Zentrale.'],
        ['Multi-RTMP', 'OBS-Erweiterung, die zwei YouTube-Streams (DE + RU) gleichzeitig rausschickt.'],
        ['PTZ-Kamera', 'Schwenk-/Zoom-Kamera, fernsteuerbar. Haben wir zwei Stück.'],
        ['X32 Rack', 'Unser Audio-Mischpult, an dem alle Mikros hängen. Bleibt unverändert.'],
        ['X-USB', 'Eingebaute Funktion im X32: ein USB-Kabel überträgt alle 32 Audiokanäle zum Mac Mini.'],
        ['Stream Deck +', 'Bedienpult mit leuchtenden Knöpfen + Drehreglern. Haben wir, wird ergänzt.'],
        ['Elgato Key Light', 'Sehr helle, dimmbare LED-Flächenleuchte für die Bühne. Per WLAN steuerbar. Haben wir 2 Stück, hängen heute schon am Stream Deck.'],
      ]),
    ],
  ),

  // 1 — Hardware-Inventar
  _Section(
    id: 's1',
    icon: '■',
    title: 'Hardware-Inventar',
    subtitle: 'Was bleibt, was fliegt raus, was kommt neu dazu',
    color: _blue,
    body: [
      _Block.heading('● Bleibt unverändert'),
      _Block.bullet('X32 Rack — Mischpult, X-USB ab Werk drin → 32 Kanäle über ein USB-Kabel'),
      _Block.bullet('SD8 — Stagebox, Übersetzer-Funkempfang. AES50 zum X32 läuft schon'),
      _Block.bullet('2× SMTAV PTZ 30x — schon im Netzwerk angeschlossen'),
      _Block.bullet('Mac Mini M1 16 GB — wird neue Stream-Zentrale, packt 2× 1080p + Whisper'),
      _Block.bullet('Stream Deck + — wird einfach um OBS-Tasten erweitert'),
      _Block.bullet('Netzwerk-Switch — schon vorhanden, weil Stream Deck die PTZ heute schon darüber steuert'),
      _Block.bullet('2× Elgato Key Light — Bühnenbeleuchtung, per WLAN dimmbar; werden über das Elgato Control Center OBS-Plugin direkt an Szenen gekoppelt (Helligkeit + Farbtemperatur pro Szene automatisch)'),
      _Block.heading('● Wird ausgebaut (nach erfolgreicher Probe)'),
      _Block.bullet('RØDECaster Video — OBS macht den Kamera-Mix direkt aus den IP-Streams'),
      _Block.bullet('Blackmagic Streaming Encoder HD — Multi-RTMP übernimmt den parallelen RU-Stream'),
      _Block.callout(
        'Geschätzter Verkaufserlös: RØDECaster ~700–900 € · Blackmagic ~300–400 € · ≈ 1.000–1.300 € kommen wieder rein.',
        icon: '€',
        color: _amber,
      ),
      _Block.heading('● Wird neu installiert (nur Software, alles kostenlos)'),
      _Block.bullet('OBS Studio'),
      _Block.bullet('OBS Multi-RTMP Plugin (parallele YouTube-Streams)'),
      _Block.bullet('obs-websocket (Steuerung von außen — Stream Deck, später iPad-App)'),
      _Block.bullet('Stream Deck OBS Plugin'),
      _Block.bullet('PTZ.OBS Plugin (optional, für Joystick + Presets)'),
      _Block.bullet('Elgato Control Center OBS Plugin (Key Lights pro Szene automatisch dimmen)'),
    ],
  ),

  // 2 — Verkabelung
  _Section(
    id: 's2',
    icon: '↯',
    title: 'Verkabelung — Vorher / Nachher',
    subtitle: '5 Geräte → 2 Geräte, 4 Signal-Wege → 1 Signal-Weg',
    color: _blue,
    body: [
      _Block.heading('Vorher'),
      _Block.paragraph(
          '4 Signal-Wege: PTZs gehen per HDMI in den RØDECaster, der zum Mac Mini, parallel läuft der Blackmagic Encoder für RU. 5 Geräte aktiv, ~36 min Aufbau.'),
      _Block.heading('Nachher'),
      _Block.paragraph(
          'PTZs hängen per Netzwerk am Switch, von dort geht alles direkt in OBS am Mac Mini. X32 schickt beide Mixe (DE + RU) per einem USB-Kabel zum Mac. Multi-RTMP sendet beide Streams parallel zu YouTube. 2 Geräte aktiv, ~8 min Aufbau.'),
      _Block.callout(
        'Was sich für die Aushilfe ändert: Vorher mussten 5 Geräte in der richtigen Reihenfolge hochfahren. Nachher: Mac Mini einschalten, X32 einschalten, Stream Deck → STREAM START. Fertig.',
        icon: '→',
        color: _blue,
      ),
    ],
  ),

  // 3 — X32 Routing
  _Section(
    id: 's3',
    icon: '♪',
    title: 'X32 — Mischpult-Konfiguration',
    subtitle: 'Wird einmal gemacht, dann per Snapshot wiederherstellbar',
    color: _amber,
    body: [
      _Block.paragraph(
          'Ziel: DE-Mix und RU-Mix gehen als zwei getrennte Tonspuren über das eine USB-Kabel zum Mac.'),
      _Block.heading('Schritt 1 — USB-Ausgänge belegen'),
      _Block.kv([
        ['USB 1', 'Bus 1 L  (DE-Mix)'],
        ['USB 2', 'Bus 1 R  (DE-Mix)'],
        ['USB 3', 'Bus 2 L  (RU-Mix, nur Übersetzer)'],
        ['USB 4', 'Bus 2 R  (RU-Mix, nur Übersetzer)'],
        ['USB 5–32', 'optional alle Einzelmikros für Multitrack-Aufnahme'],
      ]),
      _Block.heading('Schritt 2 — Busse befüllen'),
      _Block.bullet('Bus 1 (DE): Pastor, Lobpreisband, alle Saalmikros — Stereo, Pegel auf saubere –12 dBFS Spitze'),
      _Block.bullet('Bus 2 (RU): NUR der Übersetzer-Funkkanal vom SD8 — auch Stereo'),
      _Block.heading('Schritt 3 — Snapshot speichern'),
      _Block.paragraph(
          'Im X32 Edit unter Setup → Show Control → Snapshots als „Tertius Stream Setup" speichern. Dann lässt sich das ganze Routing per Knopfdruck wiederherstellen, falls jemand etwas verstellt.'),
      _Block.heading('Schritt 4 — USB anschließen'),
      _Block.paragraph(
          'Standard-Druckerkabel (USB-B → USB-A) vom X32 Rack zum Mac Mini. Im macOS unter Audio-MIDI-Setup sollte „X32" als 32×32-Gerät erscheinen.'),
    ],
    checks: [
      _Check('s3c1', 'X32 Edit am Mac installiert'),
      _Check('s3c2', 'USB-Kanäle 1–4 zugewiesen'),
      _Check('s3c3', 'Bus 1 (DE) konfiguriert + gepegelt'),
      _Check('s3c4', 'Bus 2 (RU, Übersetzer) konfiguriert + gepegelt'),
      _Check('s3c5', 'Snapshot „Tertius Stream Setup" gespeichert'),
      _Check('s3c6', 'USB-B → USB-A Kabel verlegt + Mac sieht X32 als 32×32'),
    ],
  ),

  // 4 — PTZ in OBS
  _Section(
    id: 's4',
    icon: '▶',
    title: 'PTZ-Kameras in OBS einbinden',
    subtitle: 'RTSP statt HDMI — kein zusätzliches Kabel',
    color: _green,
    body: [
      _Block.paragraph(
          'Die Kameras hängen schon im Netzwerk (deshalb steuert das Stream Deck sie heute schon). Wir holen das Bild jetzt zusätzlich per RTSP direkt nach OBS.'),
      _Block.heading('IP-Adressen notieren'),
      _Block.bullet('Front-Kamera, z.B. 192.168.1.50'),
      _Block.bullet('Seiten-Kamera, z.B. 192.168.1.51'),
      _Block.heading('RTSP-URL pro Kamera'),
      _Block.paragraph(
          'rtsp://<IP>:554/1   (Hauptstream)\nrtsp://<IP>:554/2   (Substream)\nFalls Login: rtsp://admin:admin@<IP>:554/1'),
      _Block.heading('In OBS einbinden'),
      _Block.bullet('Sources → + → Media Source, Name z.B. „PTZ Front"'),
      _Block.bullet('„Local File" abwählen'),
      _Block.bullet('Input = die RTSP-URL, Format = rtsp'),
      _Block.bullet('Reconnect Delay 2 Sek., Hardware-Decoding ein (M1 → VideoToolbox)'),
      _Block.bullet('Gleich nochmal für „PTZ Seite"'),
      _Block.callout(
        'RTSP hat typisch 1–3 Sek. Latenz. Für Live-Stream egal. Falls es im Saal stört: Buffer auf Minimum + „Restart playback when source becomes active".',
        icon: '!',
        color: _amber,
      ),
    ],
    checks: [
      _Check('s4c1', 'IP-Adressen beider PTZs notiert'),
      _Check('s4c2', 'RTSP-URL mit ffplay/VLC getestet'),
      _Check('s4c3', 'PTZ Front in OBS eingebunden'),
      _Check('s4c4', 'PTZ Seite in OBS eingebunden'),
    ],
  ),

  // 5 — OBS Audio
  _Section(
    id: 's5',
    icon: '♬',
    title: 'OBS — Audio-Spuren konfigurieren',
    subtitle: 'DE auf Track 1, RU auf Track 2',
    color: _green,
    body: [
      _Block.paragraph(
          'OBS soll den X32 als Eingang sehen und den DE-Mix auf Track 1, den RU-Mix auf Track 2 legen. Multi-RTMP nimmt dann pro YouTube-Kanal die richtige Spur.'),
      _Block.heading('Quelle anlegen'),
      _Block.paragraph('Sources → + → Audio Input Capture → Device: X32.'),
      _Block.heading('Channel-Mapping'),
      _Block.bullet('Track 1 = USB-Kanäle 1+2 (DE-Mix vom Bus 1)'),
      _Block.bullet('Track 2 = USB-Kanäle 3+4 (RU-Mix vom Bus 2)'),
      _Block.paragraph(
          'Lösung: zwei „Audio Input Capture"-Quellen anlegen — „X32 — DE-Mix" auf Track 1, „X32 — RU-Mix" auf Track 2. Beim ersten Setup machen wir das gemeinsam vor Ort, ggf. über ein Aggregate Device im Audio-MIDI-Setup.'),
      _Block.heading('Output-Settings'),
      _Block.paragraph(
          'Settings → Output → Mode Advanced. Streaming-Tab: Audio Track 1. Recording-Tab: Audio Tracks 1+2 (Backup-Aufnahme behält beide Sprachen).'),
    ],
    checks: [
      _Check('s5c1', 'X32 als Audio-Quelle in OBS sichtbar'),
      _Check('s5c2', 'DE-Mix → Track 1 gemappt'),
      _Check('s5c3', 'RU-Mix → Track 2 gemappt'),
      _Check('s5c4', 'Output-Mode auf Advanced + Tracks gesetzt'),
    ],
  ),

  // 6 — Multi-RTMP
  _Section(
    id: 's6',
    icon: '↗',
    title: 'Multi-RTMP — zwei YouTube-Kanäle parallel',
    subtitle: 'YouTube Multi-Audio nicht verfügbar → wir senden 2 Streams',
    color: _purple,
    body: [
      _Block.paragraph(
          'YouTube selbst bietet uns die Multi-Audio-Funktion (eine Sendung, mehrere Sprachspuren) leider nicht an. Lösung: parallel zwei komplette Streams an unsere zwei bestehenden Kanäle. Übernimmt das kostenlose Multi-RTMP Plugin.'),
      _Block.heading('Plugin installieren'),
      _Block.paragraph(
          'Download: github.com/sorayuki/obs-multi-rtmp/releases (macOS .pkg). Nach Installation erscheint unten rechts in OBS ein Panel „Multiple Output".'),
      _Block.heading('Konfiguration pro Kanal'),
      _Block.kv([
        ['DE Server', 'rtmp://a.rtmp.youtube.com/live2'],
        ['DE Track', 'Track 1'],
        ['DE Bitrate', '6000 kbps · Apple VT H264 (M1)'],
        ['RU Server', 'rtmp://a.rtmp.youtube.com/live2'],
        ['RU Track', 'Track 2'],
        ['RU Bitrate', '6000 kbps · Apple VT H264 (M1)'],
      ]),
      _Block.callout(
        'OBS-Settings → Stream → Service auf None setzen. Sonst sendet OBS noch einen dritten Stream parallel. Im Multi-Output-Panel reicht „Start All" und beide Streams gehen gleichzeitig live.',
        icon: '!',
        color: _amber,
      ),
    ],
    checks: [
      _Check('s6c1', 'Multi-RTMP Plugin installiert'),
      _Check('s6c2', 'YouTube DE Stream-Key eingetragen'),
      _Check('s6c3', 'YouTube RU Stream-Key eingetragen'),
      _Check('s6c4', 'OBS Stream-Service auf None gestellt'),
    ],
  ),

  // 7 — Szenen + Stream Deck
  _Section(
    id: 's7',
    icon: '▦',
    title: 'Szenen & Stream Deck Layout',
    subtitle: '6 OBS-Szenen, 8 Tasten + 4 Drehregler',
    color: _blue,
    body: [
      _Block.heading('OBS-Szenen'),
      _Block.kv([
        ['Begrüßung', 'PTZ Front (Weit), Lower Third, Key Lights 60% warm'],
        ['Lobpreis', 'Cut zwischen Front + Seite je nach Kamera-Operator'],
        ['Predigt', 'Front Close-Up auf Pastor, Lower Third, Key Lights 100% warm (Pastor angeleuchtet)'],
        ['Spende', 'Statisches Bild + Musik, Audio bleibt'],
        ['Outro', 'Tertius-Logo, Verlinkungen, Outro-Musik'],
        ['Black/Pause', 'Schwarzes Bild, Audio gemutet'],
      ]),
      _Block.heading('Stream Deck + Belegung'),
      _Block.kv([
        ['Taste 1–6', 'Szenen-Wechsel (siehe oben)'],
        ['Taste 7', 'STREAM START (rot, leuchtet wenn live)'],
        ['Taste 8', 'STREAM STOP (Doppel-Bestätigung gegen Versehen)'],
        ['Encoder 1', 'Master-Volume Track 1 (DE)'],
        ['Encoder 2', 'Master-Volume Track 2 (RU)'],
        ['Encoder 3', 'PTZ Front Preset (Weit/Pastor/Band)'],
        ['Encoder 4', 'PTZ Seite Preset (Weit/Übersetzer-Bereich)'],
        ['Touch-Strip', 'Live-Status DE/RU + Audio-Pegel + „Übersetzer aktiv"'],
      ]),
    ],
    checks: [
      _Check('s7c1', '6 OBS-Szenen angelegt'),
      _Check('s7c2', 'Stream Deck OBS Plugin installiert'),
      _Check('s7c3', 'Tasten 1–8 belegt'),
      _Check('s7c4', 'Drehencoder 1–4 belegt'),
      _Check('s7c5', 'Elgato Control Center OBS-Plugin installiert'),
      _Check('s7c6', 'Key Light Helligkeit/Farbe pro Szene gesetzt'),
    ],
  ),

  // 8 — Probe-Stream
  _Section(
    id: 's8',
    icon: '✓',
    title: 'Probe-Stream — Checkliste',
    subtitle: 'Vor dem ersten echten Sonntag immer machen!',
    color: _green,
    body: [
      _Block.callout(
        'Goldene Regel: Vor dem ersten echten Sonntag IMMER einen Probe-Stream machen — privat (nicht öffentlich), mindestens 30 Minuten stabil.',
        icon: '!',
        color: _amber,
      ),
      _Block.heading('Vorbereitung (vorabends/samstags)'),
    ],
    checks: [
      _Check('s8c1', 'Mac Mini hochfahren, OBS startet automatisch'),
      _Check('s8c2', 'X32 hochfahren, „Tertius Stream Setup" Snapshot laden'),
      _Check('s8c3', 'PTZs hochfahren, Presets per Stream Deck prüfen'),
      _Check('s8c4', 'OBS prüfen: beide PTZ-Quellen liefern Bild'),
      _Check('s8c5', 'OBS prüfen: Audio-Mixer zeigt 2 Tracks aktiv (DE+RU)'),
      _Check('s8c6', 'Stream Deck zeigt korrekte Tasten'),
      _Check('s8c7', '2 private Test-Streams in YouTube Studio erstellt'),
      _Check('s8c8', 'Stream-Keys ins Multi-RTMP Plugin kopiert'),
      _Check('s8c9', '„Start All" gedrückt, beide Streams kommen an'),
      _Check('s8c10', 'Audio: DE-Stream = Hauptmix, RU-Stream = nur Übersetzer'),
      _Check('s8c11', 'Mind. 30 Minuten stabil gelaufen'),
      _Check('s8c12', 'Verschiedene Szenen gewechselt, Stream stabil'),
      _Check('s8c13', 'Pegel-Spitzen geprüft, nichts clippt'),
    ],
  ),

  // 9 — Fallback
  _Section(
    id: 's9',
    icon: '⮌',
    title: 'Fallback-Plan',
    subtitle: 'Altes Setup bleibt 4 Wochen als Backup',
    color: _red,
    body: [
      _Block.callout(
        'Das alte Setup bleibt mindestens 4 Wochen physisch komplett erhalten. Wenn etwas crasht, sind wir in 2 Minuten zurück beim alten System.',
        icon: '✓',
        color: _green,
      ),
      _Block.heading('Während der ersten 4 Sonntage'),
      _Block.bullet('RØDECaster Video bleibt eingestöpselt aber inaktiv'),
      _Block.bullet('Blackmagic Encoder bleibt eingestöpselt aber aus'),
      _Block.bullet('HDMI-Kabel von PTZs zum RØDECaster bleiben dran'),
      _Block.bullet('Falls Crash: alten Encoder einschalten, alte Verkabelung greift wieder'),
      _Block.heading('Schnell-Switch (geübt in <2 Min)'),
      _Block.bullet('1. Mac Mini OBS stoppen'),
      _Block.bullet('2. Blackmagic Encoder einschalten'),
      _Block.bullet('3. RØDECaster aktivieren'),
      _Block.bullet('4. Alte X32-Routing-Snapshot laden'),
      _Block.bullet('5. Streams in alten Geräten starten'),
    ],
  ),

  // 10 — Aufbauzeit
  _Section(
    id: 's10',
    icon: '⏱',
    title: 'Aufbauzeit Vorher / Nachher',
    subtitle: '~36 min → ~8 min · ~24 h Ersparnis pro Jahr',
    color: _blue,
    body: [
      _Block.heading('Vorher (~36 min)'),
      _Block.kv([
        ['10 min', 'Hardware verkabeln (RØDECaster, Encoder, HDMI)'],
        ['5 min', 'X32 + SD8 hochfahren, Funkstrecke prüfen'],
        ['5 min', 'Mac OBS starten, Quellen prüfen'],
        ['8 min', 'Blackmagic Encoder konfigurieren, RU-Stream starten'],
        ['3 min', 'OBS DE-Stream starten'],
        ['5 min', 'Pegel + Bild final checken'],
      ]),
      _Block.heading('Nachher (~8 min)'),
      _Block.kv([
        ['1 min', 'Mac Mini hochfahren / aus Standby'],
        ['2 min', 'X32 hochfahren, Snapshot lädt automatisch'],
        ['2 min', 'Stream Deck → „Probe Bild + Ton"'],
        ['2 min', 'Pegel kurz prüfen'],
        ['1 min', 'Stream Deck → STREAM START'],
      ]),
    ],
  ),

  // 11 — Sprint 2 + 3
  _Section(
    id: 's11',
    icon: '✦',
    title: 'Ausblick — Sprint 2 & 3',
    subtitle: 'iPad-App + lokale Live-Transkription',
    color: _purple,
    body: [
      _Block.heading('Sprint 2 — Tertius Stream Control App (iPad)'),
      _Block.paragraph(
          'Wann? Erst wenn das aktuelle Setup 6+ Wochen stabil läuft.\nWas? iPad-App, die das Stream Deck-Konzept auf einen großen Touchscreen bringt — visueller, mehr Live-Daten, mehr Sicherheit.'),
      _Block.bullet('Großer STREAM-START Knopf, leuchtet rot wenn live'),
      _Block.bullet('Live-Vorschau beider Streams als Thumbnail'),
      _Block.bullet('Pegel-Bargraphs für DE + RU in Echtzeit'),
      _Block.bullet('Health-Dashboard: X32 / Front-Kamera / Seite-Kamera / Internet'),
      _Block.bullet('Pre-Stream Checkliste automatisch durchlaufen'),
      _Block.bullet('PTZ-Joystick + Live-Untertitel-Vorschau'),
      _Block.paragraph('Aufwand: ~45 h in Flutter, in 3 Wochenenden machbar.'),
      _Block.heading('Sprint 3 — Live-Transkription lokal auf Mac Mini'),
      _Block.paragraph(
          'whisper.cpp läuft direkt auf dem Mac Mini M1 mit Metal-Beschleunigung. Greift den Audio-Mix direkt aus OBS ab, transkribiert in Echtzeit, übersetzt via DeepL, schickt das Ergebnis an Tertius.'),
      _Block.callout(
        'Vorteile: Audio verlässt nie den Saal → 100% DSGVO-konform · Keine Server-Kosten · M1 schafft das Modell in Realtime · Bei Internet-Ausfall wird gepuffert.',
        icon: '✓',
        color: _green,
      ),
      _Block.paragraph('Aufwand: ~12 h, skript-basiert, lokal getestet bevor live.'),
    ],
  ),

  // 11b — Sprint 4 Guide-Tour
  _Section(
    id: 's11b',
    icon: '◉',
    title: 'Sprint 4 — Guide-Tour Live-Übersetzung',
    subtitle: 'Mobile Übersetzung für Führungen — jeder hört in seiner Sprache',
    color: _purple,
    body: [
      _Block.callout(
        'Heute hat praktisch jeder ein Smartphone + Kopfhörer dabei. Wir brauchen keine Funkempfänger, keine Headsets zum Verleihen, keine Pfand-Listen. Eine Tour mit 5 Personen funktioniert genauso wie eine mit 200 — null Hardware, perfekt skalierbar.',
        icon: '✦',
        color: _purple,
      ),
      _Block.heading('Wie es laufen soll'),
      _Block.bullet('Guide öffnet die Tertius-App, startet eine „Tour" und wählt Quellsprache'),
      _Block.bullet('App generiert kurzen Code (z.B. „TOUR-7421") oder QR-Code'),
      _Block.bullet('Besucher scannen Code → Live-Viewer, wählen ihre Sprache (DE/EN/RU/RO/ZU)'),
      _Block.bullet('Audio vom Guide-Handy → Whisper (lokal Mac Mini oder Cloud Run Fallback) → DeepL → Push an alle Viewer via Supabase Realtime'),
      _Block.bullet('Latenz-Ziel: unter 4 Sekunden vom Wort bis zum Untertitel'),
      _Block.heading('Was wir bauen müssen'),
      _Block.bullet('„Tour starten"-Screen für Guide (großer Mikro-Knopf, Live-Pegel)'),
      _Block.bullet('Code/QR-Generator + Beitritts-Flow für Besucher'),
      _Block.bullet('Robuste Audio-Pipeline für Mobilfunk (3G/4G im Außenbereich)'),
      _Block.bullet('Glossar für ortsspezifische Begriffe (Eigennamen, Personen, Gebäude — DeepL Glossary)'),
      _Block.bullet('Offline-Buffer falls Empfang abbricht'),
      _Block.heading('Hardware-Empfehlung Guide'),
      _Block.paragraph(
          'Beliebiges modernes Smartphone reicht — empfohlen: kabelgebundenes Lavalier-Mikrofon (~30 €) für saubere Aufnahme bei Wind.'),
      _Block.callout(
        'Tertius wird damit von „Streaming-App" zu „Echtzeit-Übersetzungs-Plattform für Gemeinde-Events". Aufwand ~25 h, Voraussetzung: Sprint 1 + 3 fertig. Glossar-Logik teilweise aus Pitlane-Construction wiederverwendbar.',
        icon: '→',
        color: _blue,
      ),
    ],
  ),

  // 12 — Risiken
  _Section(
    id: 's12',
    icon: '⚠',
    title: 'Risiken & Gegenmaßnahmen',
    subtitle: '7 Risiken — alle abgedeckt',
    color: _amber,
    body: [
      _Block.kv([
        ['RTSP instabil', 'mittel · Reconnect-Delay in OBS, Notfall HDMI-Backup über USB-Capture (~50 €)'],
        ['OBS crasht live', 'niedrig · Auto-Restart Script + OBS auto-resume on launch'],
        ['Internet-Ausfall', 'niedrig · OBS Auto-Reconnect, Encoder buffern kurz'],
        ['Stream-Key ungültig', 'niedrig · Stream Deck „Reset Keys" Knopf'],
        ['Falscher Knopf', 'hoch · STREAM STOP auf Doppel-Bestätigung'],
        ['X32 USB trennt', 'niedrig · Hochwertiges Kabel, gegen Kabelzug sichern'],
        ['Mac Mini friert', 'sehr niedrig · M1 ist extrem stabil, Watchdog optional'],
      ]),
    ],
  ),

  // 13 — Aufwand
  _Section(
    id: 's13',
    icon: 'Σ',
    title: 'Geschätzter Gesamtaufwand',
    subtitle: '~9 h Sprint 1 · auf 2–3 Wochenenden verteilbar',
    color: _green,
    body: [
      _Block.kv([
        ['2 h', 'Vorbereitung (Plugins installieren, X32 Snapshot bauen)'],
        ['2 h', 'Probe-Stream (privat, einmal komplett durchspielen)'],
        ['2 h', 'Migration durchführen (samstags vor erstem Live)'],
        ['1 h', 'Erster Live-Test (mit Backup-Verkabelung)'],
        ['1 h', 'Stream Deck Layout finalisieren'],
        ['1 h', 'Doku für Aushilfen schreiben (1-Pager)'],
      ]),
    ],
  ),

  // 14 — Nächste Schritte
  _Section(
    id: 's14',
    icon: '→',
    title: 'Nächste Schritte',
    subtitle: 'Wo geht es jetzt los?',
    color: _blue,
    body: [
      _Block.paragraph(
          'Diese Doku lebt — Notizen pro Sektion einfach ergänzen, Fragen unten reinschreiben. Jeder Browser speichert seine eigenen Notizen lokal.'),
    ],
    checks: [
      _Check('s14c1', 'Diese Doku in Ruhe gelesen, Fragen gesammelt'),
      _Check('s14c2', 'Termine gesetzt für Vorbereitung + Probe + erstes Live'),
      _Check('s14c3', 'Plugins schon vorab heruntergeladen'),
      _Check('s14c4', 'PTZ-IPs + RTSP-URLs beim nächsten Saal-Termin notiert'),
      _Check('s14c5', 'Erster Migration-Schritt gemeinsam mit Marcel durchgegangen'),
    ],
  ),
];
