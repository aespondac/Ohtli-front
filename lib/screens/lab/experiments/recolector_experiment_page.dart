import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../theme/colors.dart';

class RecolectorExperimentPage extends StatefulWidget {
  final VoidCallback onBack;

  const RecolectorExperimentPage({super.key, required this.onBack});

  @override
  State<RecolectorExperimentPage> createState() => _RecolectorExperimentPageState();
}

class _RecolectorExperimentPageState extends State<RecolectorExperimentPage> {
  final TextEditingController _latController = TextEditingController(text: '19.432608'); // Zócalo CDMX
  final TextEditingController _lngController = TextEditingController(text: '-99.133209');
  final TextEditingController _radiusController = TextEditingController(text: '1000');
  
  String? _currentJobId;
  Set<String> _selectedPois = {};
  bool _isReplicating = false;

  void _runExploration() async {
    final lat = double.tryParse(_latController.text);
    final lng = double.tryParse(_lngController.text);
    final radius = int.tryParse(_radiusController.text);

    if (lat == null || lng == null || radius == null) return;

    // Crear el job en Firestore
    final docRef = await FirebaseFirestore.instance.collection('recolector_jobs').add({
      'status': 'pending',
      'progress': 0,
      'message': 'Encolando...',
      'created_at': FieldValue.serverTimestamp(),
      'request': {
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'max_pois': 20, // Límite por defecto para pruebas en UI
      }
    });

    setState(() {
      _currentJobId = docRef.id;
      _selectedPois.clear();
    });
  }

  Future<void> _replicateToProd() async {
    if (_selectedPois.isEmpty) return;
    
    setState(() => _isReplicating = true);
    
    try {
      final response = await http.post(
        Uri.parse('https://api.ohtli.quest/v1/api/recolector/replicate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'poi_ids': _selectedPois.toList()}),
      );
      
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Replicación exitosa.', style: GoogleFonts.inter()), backgroundColor: OhtliColors.stormyTeal),
          );
        }
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falló la replicación: $e', style: GoogleFonts.inter()), backgroundColor: OhtliColors.xoconostle),
        );
      }
    } finally {
      if (mounted) setState(() => _isReplicating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EEE9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF0A090C)), onPressed: widget.onBack),
        title: Text('Caza Lugares (Motor Recolector)', style: GoogleFonts.outfit(color: const Color(0xFF0A090C), fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildForm(),
                const SizedBox(height: 32),
                if (_currentJobId != null) _buildJobStream(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Configuración de Exploración', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: TextField(controller: _latController, decoration: const InputDecoration(labelText: 'Latitud'))),
              const SizedBox(width: 16),
              Expanded(child: TextField(controller: _lngController, decoration: const InputDecoration(labelText: 'Longitud'))),
              const SizedBox(width: 16),
              Expanded(child: TextField(controller: _radiusController, decoration: const InputDecoration(labelText: 'Radio (m)'))),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _runExploration,
              icon: const Icon(Icons.travel_explore_rounded),
              label: const Text('Explorar Zona (Sandbox)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobStream() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('recolector_jobs').doc(_currentJobId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final status = data['status'] ?? 'pending';
        final progress = data['progress'] ?? 0;
        final message = data['message'] ?? '';

        if (status == 'completed' && data.containsKey('result')) {
          return _buildResults(data['result']['results'] as List);
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              if (status == 'error')
                Text('Error: ${data['error_detail']}', style: GoogleFonts.firaCode(color: OhtliColors.xoconostle))
              else ...[
                CircularProgressIndicator(value: progress > 0 ? progress / 100 : null, color: OhtliColors.stormyTeal),
                const SizedBox(height: 24),
                Text('$progress%', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(message, style: GoogleFonts.inter(fontSize: 16, color: Colors.black54)),
              ]
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults(List results) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Resultados (${results.length})', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold)),
            if (_selectedPois.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _isReplicating ? null : _replicateToProd,
                icon: _isReplicating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_upload_rounded),
                label: Text('Replicar a Producción (${_selectedPois.length})'),
                style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.cempasuchil, foregroundColor: Colors.black),
              )
          ],
        ),
        const SizedBox(height: 16),
        ...results.map((r) {
          final id = r['poi_id'] ?? '';
          final name = r['name'] ?? 'Desconocido';
          final recipe = r['recipe'] ?? '';
          
          final isSelected = _selectedPois.contains(id);
          
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: CheckboxListTile(
              value: isSelected,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedPois.add(id);
                  } else {
                    _selectedPois.remove(id);
                  }
                });
              },
              title: Text(name, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              subtitle: Text(recipe, style: GoogleFonts.firaCode(fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis),
              activeColor: OhtliColors.stormyTeal,
            ),
          );
        }),
      ],
    );
  }
}
