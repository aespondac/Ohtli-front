import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/place_search.dart';
import '../theme/colors.dart';
import 'ohtli_ui.dart';

/// Píldora de búsqueda con sugerencias de Google Places dentro de la CDMX.
/// Al elegir una sugerencia entrega su nombre y coordenadas en [onSelected].
class PlaceSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final void Function(String name, double lat, double lng) onSelected;
  final VoidCallback onCleared;

  const PlaceSearchField({
    super.key,
    required this.controller,
    required this.onSelected,
    required this.onCleared,
    this.hintText = 'Escribe una dirección, colonia o lugar…',
  });

  @override
  State<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<PlaceSearchField> {
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _loading = false;
  bool _noResults = false;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() => _noResults = false);
    if (value.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final id = ++_requestId;
      setState(() => _loading = true);
      final found = await PlaceSearch.suggest(value);
      if (!mounted || id != _requestId) return;
      setState(() {
        _loading = false;
        _suggestions = found;
        _noResults = found.isEmpty && PlaceSearch.available;
      });
    });
  }

  Future<void> _pick(PlaceSuggestion s) async {
    setState(() {
      _suggestions = const [];
      _loading = true;
    });
    final place = await PlaceSearch.resolve(s);
    if (!mounted) return;
    setState(() => _loading = false);
    if (place == null) {
      setState(() => _noResults = true);
      return;
    }
    widget.controller.text = s.title;
    widget.onSelected(s.title, place.lat, place.lng);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.only(left: 18, right: 6),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: OhtliColors.cardBorder),
            boxShadow: OhtliUi.softShadow(),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: OhtliColors.accentText, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  onChanged: _onChanged,
                  onSubmitted: (_) {
                    if (_suggestions.isNotEmpty) _pick(_suggestions.first);
                  },
                  style: GoogleFonts.inter(fontSize: 14.5, color: OhtliColors.onyx, fontWeight: FontWeight.w500),
                  cursorColor: OhtliColors.stormyTeal,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: OhtliColors.stormyTeal)),
                )
              else if (widget.controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'Borrar',
                  icon: Icon(Icons.close_rounded, size: 18, color: OhtliColors.subtleText),
                  onPressed: () {
                    widget.controller.clear();
                    setState(() {
                      _suggestions = const [];
                      _noResults = false;
                    });
                    widget.onCleared();
                  },
                ),
            ],
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: OhtliColors.cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: OhtliColors.cardBorder),
              boxShadow: OhtliUi.softShadow(),
            ),
            child: Column(
              children: [
                for (final s in _suggestions)
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _pick(s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 18, color: OhtliColors.stormyTeal),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                        fontSize: 13.5, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                                if (s.subtitle.isNotEmpty)
                                  Text(s.subtitle,
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: OhtliUi.body(size: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          )
        else if (_noResults)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 18),
            child: Text('No encontramos ese lugar en la Ciudad de México. Prueba con otra dirección o colonia.',
                style: OhtliUi.body(size: 12)),
          ),
      ],
    );
  }
}
