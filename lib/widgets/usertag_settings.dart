import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/profile_directory.dart';
import '../services/user_private_data.dart';
import '../theme/colors.dart';
import 'ohtli_ui.dart';

/// Cuenta → Privacidad: cambiar el @usertag y decidir si te pueden encontrar por
/// correo o teléfono verificados (solo si el perfil es público).
class UsertagSettings extends StatefulWidget {
  const UsertagSettings({super.key});

  @override
  State<UsertagSettings> createState() => _UsertagSettingsState();
}

class _UsertagSettingsState extends State<UsertagSettings> {
  final _tag = TextEditingController();
  String? _current;
  String? _status; // checking, ok, taken, invalid, reserved, prohibited
  bool _saving = false;
  bool _discoverable = true;
  String? _message;
  Timer? _debounce;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = _user;
    if (user == null) return;
    try {
      final data = await UserPrivateData.get(user.uid);
      if (!mounted) return;
      setState(() {
        _current = data['usertag'] as String?;
        _tag.text = _current ?? '';
        _discoverable = data['contact_discoverable'] != false;
        if (_current != null) _status = 'ok';
      });
    } catch (_) {}
  }

  void _check(String raw) {
    _debounce?.cancel();
    final tag = ProfileDirectory.normalizeTag(raw);
    if (raw.trim().isEmpty) return setState(() => _status = null);
    if (tag == null) return setState(() => _status = 'invalid');
    if (tag == _current) return setState(() => _status = 'ok');
    final problem = ProfileDirectory.tagProblem(tag);
    if (problem != null) return setState(() => _status = problem);
    setState(() => _status = 'checking');
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final user = _user;
      if (user == null) return;
      bool free;
      try {
        free = await ProfileDirectory.isTagAvailable(tag, user.uid);
      } catch (_) {
        free = true;
      }
      if (mounted && ProfileDirectory.normalizeTag(_tag.text) == tag) setState(() => _status = free ? 'ok' : 'taken');
    });
  }

  Future<void> _saveTag() async {
    final user = _user;
    final tag = ProfileDirectory.normalizeTag(_tag.text);
    if (user == null || tag == null || _status != 'ok' || tag == _current) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await ProfileDirectory.claimTag(user.uid, tag);
      if (mounted) {
        setState(() {
          _current = tag;
          _message = 'Tu usertag ahora es @$tag.';
        });
      }
    } on StateError catch (e) {
      if (mounted) setState(() => _message = e.message);
    } on FirebaseException catch (_) {
      if (mounted) setState(() => _message = 'No pudimos guardarlo. Prueba otro usertag.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setDiscoverable(bool v) async {
    final user = _user;
    if (user == null) return;
    setState(() => _discoverable = v);
    await UserPrivateData.save(user.uid, {'contact_discoverable': v});
  }

  @override
  Widget build(BuildContext context) {
    final help = switch (_status) {
      'checking' => ('Revisando…', OhtliColors.subtleText),
      'ok' => (ProfileDirectory.normalizeTag(_tag.text) == _current ? 'Es tu usertag.' : '¡Está libre!', OhtliColors.accentText),
      'taken' => ('Ya lo tiene alguien más.', OhtliColors.xoconostle),
      'invalid' => ('De 3 a 20: letras, números, punto o guion bajo.', OhtliColors.xoconostle),
      'reserved' => ('Ese usertag está reservado.', OhtliColors.xoconostle),
      'prohibited' => ('Ese usertag no está permitido.', OhtliColors.xoconostle),
      _ => ('Tu nombre único en Ohtli.', OhtliColors.subtleText),
    };
    final canSave = _status == 'ok' && ProfileDirectory.normalizeTag(_tag.text) != _current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tu usertag', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.onyx, fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Semantics(
                label: 'Usertag',
                textField: true,
                child: TextField(
                  controller: _tag,
                  onChanged: _check,
                  autocorrect: false,
                  style: GoogleFonts.inter(color: OhtliColors.onyx, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'tu.nombre',
                    prefixIcon: Icon(Icons.alternate_email_rounded, color: OhtliColors.accentText),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            OhtliPrimaryButton(compact: true, label: 'Guardar', loading: _saving, onPressed: canSave && !_saving ? _saveTag : null),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          liveRegion: true,
          child: Text(_message ?? help.$1,
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: _message != null ? OhtliColors.accentText : help.$2)),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          activeThumbColor: OhtliColors.stormyTeal,
          contentPadding: EdgeInsets.zero,
          title: Text('Que me encuentren por correo o teléfono',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.onyx, fontSize: 14)),
          subtitle: Text(
            'Si tu perfil es público, quien escriba tu correo o tu teléfono verificado completos te verá en Amigos. Nunca se muestran.',
            style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx.withValues(alpha: 0.55)),
          ),
          value: _discoverable,
          onChanged: _setDiscoverable,
        ),
      ],
    );
  }
}
