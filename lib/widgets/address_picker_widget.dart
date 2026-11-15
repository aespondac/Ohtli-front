// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/colors.dart';

// Global flag to prevent duplicate platform view registration
bool _isOhtliMapPlatformViewRegistered = false;

/// Reusable Address Picker widget for Ohtli.
/// Contains search autocomplete, styled Google Map, draggable precision pin,
/// and locked CDMX, Mexico inputs.
class AddressPickerWidget extends StatefulWidget {
  final Map<String, dynamic>? initialAddress;
  final ValueChanged<Map<String, dynamic>> onSave;
  final VoidCallback onCancel;
  final List<String> existingNames;

  const AddressPickerWidget({
    super.key,
    this.initialAddress,
    required this.onSave,
    required this.onCancel,
    this.existingNames = const [],
  });

  @override
  State<AddressPickerWidget> createState() => _AddressPickerWidgetState();
}

class _AddressPickerWidgetState extends State<AddressPickerWidget> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _customNameController;
  late TextEditingController _streetController;
  late TextEditingController _suburbController;
  late TextEditingController _zipController;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  late TextEditingController _countryController;
  final TextEditingController _searchController = TextEditingController();

  // Category state
  String _selectedCategory = 'Otro';

  // Coordinate and State validation state
  double? _selectedLat;
  double? _selectedLng;
  String? _googleState;

  // Autocomplete state
  List<Map<String, String>> _predictions = [];
  bool _isSearchingPredictions = false;
  Timer? _debounceTimer;
  String? _autocompleteError;
  String? _cdmxBoundaryError;

  static const List<String> _blacklistedMunicipalities = [
    'atizapán', 'atizapan',
    'naucalpan',
    'tlalnepantla',
    'huixquilucan',
    'ecatepec',
    'nezahualcóyotl', 'nezahualcoyotl', 'neza',
    'chimalhuacán', 'chimalhuacan',
    'nicolás romero', 'nicolas romero',
    'coacalco',
    'tultitlán', 'tultitlan',
    'cuautitlán', 'cuautitlan',
    'chalco',
    'ixtapaluca',
    'tecámac', 'tecamac',
    'la paz',
    'valle de chalco',
    'chicoloapan',
    'lopez mateos', 'lópez mateos',
    'xonacatlán', 'xonacatlan',
    'lerma',
    'toluca',
    'metepec',
    'ocoyoacac',
  ];

  bool _isCoordinateInCDMX(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    // Bounding Box para la Ciudad de México (CDMX)
    // Latitudes: 19.00 a 19.60, Longitudes: -99.38 a -98.90
    return lat >= 19.00 && lat <= 19.60 && lng >= -99.38 && lng <= -98.90;
  }

  bool _isOfficialCDMX(String? stateName) {
    if (stateName == null) return false;
    final name = stateName.toLowerCase().trim();
    return name.contains('ciudad de méxico') ||
           name.contains('cdmx') ||
           name.contains('distrito federal') ||
           name == 'df' ||
           name == 'd.f.';
  }

  bool _isValidCDMXZip(String? zip) {
    if (zip == null) return false;
    final cleanZip = zip.trim().replaceAll(RegExp(r'\D'), '');
    if (cleanZip.length != 5) return false;
    final prefix = int.tryParse(cleanZip.substring(0, 2));
    return prefix != null && prefix >= 1 && prefix <= 16;
  }

  @override
  void initState() {
    super.initState();

    // Initialize controllers with initial address or default CDMX constants
    final addr = widget.initialAddress;
    _customNameController = TextEditingController(text: addr?['customName'] ?? '');
    _selectedCategory = addr?['category'] ?? 'Otro';
    _selectedLat = addr?['lat'] != null ? (addr?['lat'] as num).toDouble() : null;
    _selectedLng = addr?['lng'] != null ? (addr?['lng'] as num).toDouble() : null;
    _googleState = addr?['state'];

    _streetController = TextEditingController(text: addr?['street'] ?? '');
    _suburbController = TextEditingController(text: addr?['suburb'] ?? '');
    _zipController = TextEditingController(text: addr?['zip'] ?? '');
    _cityController = TextEditingController(text: addr?['city'] ?? '');
    // Locked to CDMX / Mexico per guidelines
    _stateController = TextEditingController(text: 'Ciudad de México');
    _countryController = TextEditingController(text: 'México');

    _registerMapPlatformView();
    _registerMapCallback();
    _injectGooglePlacesApi();

    // Trigger initial geocoding or center
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kIsWeb && globalContext.has('mountOhtliAddressMap')) {
        globalContext.callMethod('mountOhtliAddressMap'.toJS, OhtliSettings.instance.isDarkMode.toJS);

        final isNew = widget.initialAddress == null;
        // Nueva: el mapa arranca en la ciudad y los campos vacíos hasta que la persona busque
        // o mueva el pin. Editar: centra en la dirección guardada.
        if (!isNew) {
          final lat = _selectedLat;
          final lng = _selectedLng;
          if (lat != null && lng != null && globalContext.has('panOhtliAddressMapToLatLng')) {
            globalContext.callMethodVarArgs('panOhtliAddressMapToLatLng'.toJS, <JSAny?>[(lat).jsify(), (lng).jsify()]);
          } else {
            final fullAddr = "${_streetController.text}, ${_suburbController.text}, C.P. ${_zipController.text}, ${_cityController.text}, Ciudad de México, México";
            if (globalContext.has('geocodeAndPanOhtliAddressMap')) {
              globalContext.callMethodVarArgs('geocodeAndPanOhtliAddressMap'.toJS, <JSAny?>[(fullAddr).jsify()]);
            }
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _customNameController.dispose();
    _streetController.dispose();
    _suburbController.dispose();
    _zipController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _countryController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _registerMapPlatformView() {
    if (kIsWeb && !_isOhtliMapPlatformViewRegistered) {
      ui_web.platformViewRegistry.registerViewFactory('ohtli-address-map', (int viewId) {
        final element = web.HTMLDivElement()
          ..id = 'ohtli-map-container'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.borderRadius = '16px'
          ..style.overflow = 'hidden';
        return element;
      });
      _isOhtliMapPlatformViewRegistered = true;
    }
  }

  void _registerMapCallback() {
    if (kIsWeb) {
      // Binds active widget state to maps reverse-geocoding drags
      globalContext['ohtliMapCallback'] = (((String jsonStr) {
        try {
          final data = json.decode(jsonStr);
          if (mounted) {
            final double? lat = data['lat'] != null ? (data['lat'] as num).toDouble() : null;
            final double? lng = data['lng'] != null ? (data['lng'] as num).toDouble() : null;
            final String? googleState = data['state'] as String?;
            final String? zip = data['zip'] as String?;

            final bool isCoordsInCDMX = _isCoordinateInCDMX(lat, lng);
            final bool isStateCDMX = _isOfficialCDMX(googleState);
            final bool isZipCDMX = zip == null || zip.isEmpty || _isValidCDMXZip(zip);

            final String streetText = (data['street'] as String? ?? '').toLowerCase();
            final String suburbText = (data['suburb'] as String? ?? '').toLowerCase();
            final String cityText = (data['city'] as String? ?? '').toLowerCase();
            final String stateText = (googleState ?? '').toLowerCase();

            bool containsBlacklisted = false;
            for (final term in _blacklistedMunicipalities) {
              if (streetText.contains(term) ||
                  suburbText.contains(term) ||
                  cityText.contains(term) ||
                  stateText.contains(term)) {
                containsBlacklisted = true;
                break;
              }
            }

            if (lat != null && lng != null && (!isCoordsInCDMX || !isStateCDMX || !isZipCDMX || containsBlacklisted)) {
              setState(() {
                _cdmxBoundaryError = "El pin del mapa está fuera de la Ciudad de México. Ohtli por ahora solo opera dentro de la CDMX.";
                _streetController.text = '';
                _suburbController.text = '';
                _zipController.text = '';
                _cityController.text = '';
                _selectedLat = null;
                _selectedLng = null;
                _googleState = null;
              });
            } else {
              setState(() {
                _cdmxBoundaryError = null;
                _streetController.text = data['street'] as String? ?? '';
                _suburbController.text = data['suburb'] as String? ?? '';
                _zipController.text = data['zip'] as String? ?? '';
                _cityController.text = data['city'] as String? ?? '';
                _stateController.text = 'Ciudad de México';
                _countryController.text = 'México';
                _selectedLat = lat;
                _selectedLng = lng;
                _googleState = googleState;
              });
            }
          }
        } catch (e) {
          print("Error parsing map callback: $e");
        }
      })).toJS;
    }
  }

  void _injectGooglePlacesApi() {
    if (!kIsWeb) return;
    const mapsApiKey = String.fromEnvironment('mapsApiKey');
    const apiKey = String.fromEnvironment('apiKey');
    final activeKey = mapsApiKey.isNotEmpty ? mapsApiKey : apiKey;
    if (activeKey.isEmpty) return;

    if (web.document.getElementById('google-maps-places-script') == null) {
      final script = web.HTMLScriptElement()
        ..id = 'google-maps-places-script'
        ..src = 'https://maps.googleapis.com/maps/api/js?key=$activeKey&libraries=places&language=es&region=MX'
        ..async = true;
      web.document.head!.append(script);
    }

    if (web.document.getElementById('ohtli-places-helpers') == null || !globalContext.has('getOhtliPlacePredictions')) {
      web.document.getElementById('ohtli-places-helpers')?.remove();

      final helpersScript = web.HTMLScriptElement()
        ..id = 'ohtli-places-helpers'
        ..text = '''
        window.getOhtliPlacePredictions = function(input, callback) {
          if (!window.google || !window.google.maps || !window.google.maps.places) {
            callback(JSON.stringify({ error: "Google Maps library or Places library not fully loaded yet." }));
            return;
          }
          const service = new google.maps.places.AutocompleteService();
          service.getPlacePredictions({
            input: input,
            bounds: new google.maps.LatLngBounds(
              { lat: 19.00, lng: -99.38 }, // Southwest CDMX
              { lat: 19.60, lng: -98.90 }  // Northeast CDMX
            ),
            componentRestrictions: { country: 'mx' }
          }, (predictions, status) => {
            if (status !== google.maps.places.PlacesServiceStatus.OK || !predictions) {
              console.error("Google Places Predictions error status:", status);
              callback(JSON.stringify({ error: status }));
              return;
            }
            
            // Filter predictions to only include Ciudad de México (CDMX) keywords
            const cdmxKeywords = ["ciudad de méxico", "cdmx", "distrito federal", "d.f.", "d. f.", "df"];
            const filtered = predictions.filter(p => {
              const desc = p.description.toLowerCase();
              return cdmxKeywords.some(kw => desc.includes(kw));
            });

            const mapped = filtered.map(p => ({
              description: p.description,
              placeId: p.place_id
            }));
            callback(JSON.stringify({ predictions: mapped }));
          });
        };

        window.getOhtliPlaceDetails = function(placeId, callback) {
          if (!window.google || !window.google.maps || !window.google.maps.places) {
            callback(JSON.stringify({ error: "Google Maps API not loaded" }));
            return;
          }
          const dummy = document.createElement('div');
          const service = new google.maps.places.PlacesService(dummy);
          service.getDetails({
            placeId: placeId,
            fields: ['address_components', 'formatted_address', 'geometry']
          }, (result, status) => {
            if (status !== google.maps.places.PlacesServiceStatus.OK || !result) {
              console.error("Google Places Details error status:", status);
              callback(JSON.stringify({ error: status }));
              return;
            }
            
            let street = "";
            let streetNumber = "";
            let suburb = "";
            let zip = "";
            let city = "";
            let state = "";
            let country = "";
            let lat = null;
            let lng = null;

            if (result.geometry && result.geometry.location) {
              lat = result.geometry.location.lat();
              lng = result.geometry.location.lng();
            }

            if (result.address_components) {
              for (const component of result.address_components) {
                const types = component.types;
                if (types.includes("route")) {
                  street = component.long_name;
                } else if (types.includes("street_number")) {
                  streetNumber = component.long_name;
                } else if (types.includes("sublocality") || types.includes("sublocality_level_1") || types.includes("neighborhood")) {
                  suburb = component.long_name;
                } else if (types.includes("postal_code")) {
                  zip = component.long_name;
                } else if (types.includes("locality") || types.includes("administrative_area_level_2")) {
                  city = component.long_name;
                } else if (types.includes("administrative_area_level_1")) {
                  state = component.long_name;
                } else if (types.includes("country")) {
                  country = component.long_name;
                }
              }
            }
            
            const streetAndNum = streetNumber ? street + " " + streetNumber : street;

            callback(JSON.stringify({
              street: streetAndNum,
              suburb: suburb,
              zip: zip,
              city: city,
              state: state,
              country: country,
              lat: lat,
              lng: lng
            }));
          });
        };

        const ohtliMapStyles = [
          { elementType: "geometry", stylers: [{ color: "#F0EEE9" }] },
          { elementType: "labels.text.fill", stylers: [{ color: "#353839" }] },
          { elementType: "labels.text.stroke", stylers: [{ color: "#F0EEE9" }] },
          { featureType: "administrative", elementType: "geometry.stroke", stylers: [{ color: "#D1CDC4" }] },
          { featureType: "landscape.natural", elementType: "geometry", stylers: [{ color: "#E3DFD5" }] },
          { featureType: "poi", elementType: "geometry", stylers: [{ color: "#E3DFD5" }] },
          { featureType: "poi", elementType: "labels.text.fill", stylers: [{ color: "#6C3953" }] },
          { featureType: "road", elementType: "geometry", stylers: [{ color: "#FFFFFF" }] },
          { featureType: "road.highway", elementType: "geometry", stylers: [{ color: "#D1CDC4" }] },
          { featureType: "road.highway", elementType: "geometry.stroke", stylers: [{ color: "#B8B3A8" }] },
          { featureType: "road.arterial", elementType: "geometry", stylers: [{ color: "#FFFFFF" }] },
          { featureType: "road.local", elementType: "geometry", stylers: [{ color: "#FFFFFF" }] },
          { featureType: "transit.line", elementType: "geometry", stylers: [{ color: "#D1CDC4" }] },
          { featureType: "transit.station", elementType: "geometry", stylers: [{ color: "#E3DFD5" }] },
          { featureType: "water", elementType: "geometry", stylers: [{ color: "#2C666E" }] },
          { featureType: "water", elementType: "labels.text.fill", stylers: [{ color: "#FFFFFF" }] }
        ];

        const ohtliMapStylesDark = [
          { elementType: "geometry", stylers: [{ color: "#1E1E22" }] },
          { elementType: "labels.text.fill", stylers: [{ color: "#B9B5AC" }] },
          { elementType: "labels.text.stroke", stylers: [{ color: "#1E1E22" }] },
          { featureType: "administrative", elementType: "geometry.stroke", stylers: [{ color: "#3A3A42" }] },
          { featureType: "poi", elementType: "geometry", stylers: [{ color: "#25252B" }] },
          { featureType: "poi", elementType: "labels.text.fill", stylers: [{ color: "#C89AB2" }] },
          { featureType: "road", elementType: "geometry", stylers: [{ color: "#34343C" }] },
          { featureType: "road.highway", elementType: "geometry", stylers: [{ color: "#4A4A54" }] },
          { featureType: "transit.line", elementType: "geometry", stylers: [{ color: "#3A3A42" }] },
          { featureType: "water", elementType: "geometry", stylers: [{ color: "#1F4A50" }] },
          { featureType: "water", elementType: "labels.text.fill", stylers: [{ color: "#9FD0D6" }] }
        ];

        // El mapa se crea unos milisegundos después de pedirlo: lo que se pida antes (centrar
        // en una dirección guardada) queda pendiente y se aplica al crearlo.
        window.mountOhtliAddressMap = function(isDark) {
          window.ohtliCurrentMap = null;
          window.ohtliMapUserMoved = false;
          const checkExist = setInterval(function() {
            const mapDiv = document.getElementById('ohtli-map-container');
            if (mapDiv && window.google && window.google.maps) {
              clearInterval(checkExist);
              
              const defaultLatLng = { lat: 19.4326, lng: -99.1332 }; // CDMX
              const pending = window.ohtliPendingCenter;
              window.ohtliPendingCenter = null;
              const map = new google.maps.Map(mapDiv, {
                center: pending || defaultLatLng,
                zoom: pending ? 16 : 13,
                disableDefaultUI: true,
                zoomControl: true,
                gestureHandling: 'greedy',
                styles: isDark ? ohtliMapStylesDark : ohtliMapStyles
              });
              
              window.ohtliCurrentMap = map;
              const geocoder = new google.maps.Geocoder();
              // Solo cuando la persona mueve el mapa se llenan los campos con lo que hay bajo el pin
              map.addListener('dragstart', () => { window.ohtliMapUserMoved = true; });
              if (window.ohtliPendingAddress) {
                const addr = window.ohtliPendingAddress;
                window.ohtliPendingAddress = null;
                window.geocodeAndPanOhtliAddressMap(addr);
              }
              
              map.addListener('idle', () => {
                if (window.ohtliMapProgrammaticPanning || !window.ohtliMapUserMoved) {
                  return;
                }
                const center = map.getCenter();
                const lat = center.lat();
                const lng = center.lng();
                
                geocoder.geocode({ location: { lat, lng } }, (results, status) => {
                  if (status === 'OK' && results[0]) {
                    const result = results[0];
                    
                    let street = "";
                    let streetNumber = "";
                    let suburb = "";
                    let zip = "";
                    let city = "";
                    let state = "";
                    let country = "";

                    if (result.address_components) {
                      for (const component of result.address_components) {
                        const types = component.types;
                        if (types.includes("route")) {
                          street = component.long_name;
                        } else if (types.includes("street_number")) {
                          streetNumber = component.long_name;
                        } else if (types.includes("sublocality") || types.includes("sublocality_level_1") || types.includes("neighborhood")) {
                          suburb = component.long_name;
                        } else if (types.includes("postal_code")) {
                          zip = component.long_name;
                        } else if (types.includes("locality") || types.includes("administrative_area_level_2")) {
                          city = component.long_name;
                        } else if (types.includes("administrative_area_level_1")) {
                          state = component.long_name;
                        } else if (types.includes("country")) {
                          country = component.long_name;
                        }
                      }
                    }
                    
                    const streetAndNum = streetNumber ? street + " " + streetNumber : street;
                    
                    if (window.ohtliMapCallback) {
                      window.ohtliMapCallback(JSON.stringify({
                        street: streetAndNum,
                        suburb: suburb,
                        zip: zip,
                        city: city,
                        state: state,
                        country: country,
                        lat: lat,
                        lng: lng
                      }));
                    }
                  }
                });
              });
            }
          }, 100);
        };

        window.panOhtliAddressMapToLatLng = function(lat, lng) {
          if (!window.ohtliCurrentMap) { window.ohtliPendingCenter = { lat: lat, lng: lng }; return; }
          window.ohtliMapProgrammaticPanning = true;
          window.ohtliCurrentMap.setCenter({ lat: lat, lng: lng });
          window.ohtliCurrentMap.setZoom(16);
          setTimeout(() => {
            window.ohtliMapProgrammaticPanning = false;
          }, 1000);
        };

        window.geocodeAndPanOhtliAddressMap = function(addressStr) {
          if (!window.google || !window.google.maps || !window.ohtliCurrentMap) { window.ohtliPendingAddress = addressStr; return; }
          const geocoder = new google.maps.Geocoder();
          window.ohtliMapProgrammaticPanning = true;
          geocoder.geocode({ address: addressStr, componentRestrictions: { country: 'mx' } }, (results, status) => {
            if (status === 'OK' && results[0]) {
              const loc = results[0].geometry.location;
              if (window.ohtliCurrentMap) {
                window.ohtliCurrentMap.setCenter(loc);
                window.ohtliCurrentMap.setZoom(16);
              }
            }
            setTimeout(() => {
              window.ohtliMapProgrammaticPanning = false;
            }, 1000);
          });
        };
      ''';
      web.document.head!.append(helpersScript);
    }
  }

  Future<void> _onAddressInputChanged(String val) async {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    if (val.trim().isEmpty) {
      setState(() {
        _predictions = [];
        _autocompleteError = null;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() {
        _isSearchingPredictions = true;
        _autocompleteError = null;
      });
      try {
        if (globalContext.has('getOhtliPlacePredictions')) {
          globalContext.callMethodVarArgs('getOhtliPlacePredictions'.toJS, <JSAny?>[(val).jsify(), (((JSAny? result) {
              if (result != null && mounted) {
                final String jsonStr = (result as JSString).toDart;
                final Map<String, dynamic> decoded = json.decode(jsonStr) as Map<String, dynamic>;
                
                if (decoded.containsKey('error')) {
                  setState(() {
                    _autocompleteError = decoded['error'] as String?;
                    _predictions = [];
                  });
                } else if (decoded.containsKey('predictions')) {
                  final List<Map<String, String>> items = [];
                  final List<dynamic> list = decoded['predictions'] as List;
                  for (final item in list) {
                    final map = item as Map<String, dynamic>;
                    items.add({
                      'description': map['description'] as String? ?? '',
                      'placeId': map['placeId'] as String? ?? '',
                    });
                  }
                  setState(() {
                    _predictions = items;
                    _autocompleteError = null;
                  });
                }
              }
              setState(() => _isSearchingPredictions = false);
            })).toJS]);
        } else {
          setState(() {
            _autocompleteError = "Helpers script not loaded on window context.";
            _isSearchingPredictions = false;
          });
        }
      } catch (e) {
        print("Predictions error: $e");
        setState(() {
          _autocompleteError = e.toString();
          _isSearchingPredictions = false;
        });
      }
    });
  }

  Future<void> _selectPrediction(Map<String, String> prediction) async {
    final placeId = prediction['placeId'];
    if (placeId == null || placeId.isEmpty) return;

    setState(() {
      _predictions = [];
      _searchController.text = prediction['description'] ?? '';
      _isSearchingPredictions = true;
      _autocompleteError = null;
      _cdmxBoundaryError = null;
    });

    try {
      if (globalContext.has('getOhtliPlaceDetails')) {
        globalContext.callMethodVarArgs('getOhtliPlaceDetails'.toJS, <JSAny?>[(placeId).jsify(), (((JSAny? result) {
            if (result != null && mounted) {
              final String jsonStr = (result as JSString).toDart;
              final Map<String, dynamic> decoded = json.decode(jsonStr) as Map<String, dynamic>;

              if (decoded.containsKey('error')) {
                setState(() {
                  _autocompleteError = decoded['error'] as String?;
                });
              } else {
                final double? lat = decoded['lat'] != null ? (decoded['lat'] as num).toDouble() : null;
                final double? lng = decoded['lng'] != null ? (decoded['lng'] as num).toDouble() : null;
                final String? googleState = decoded['state'] as String?;
                final String? zip = decoded['zip'] as String?;

                final bool isCoordsInCDMX = _isCoordinateInCDMX(lat, lng);
                final bool isStateCDMX = _isOfficialCDMX(googleState);
                final bool isZipCDMX = zip == null || zip.isEmpty || _isValidCDMXZip(zip);

                final String streetText = (decoded['street'] as String? ?? '').toLowerCase();
                final String suburbText = (decoded['suburb'] as String? ?? '').toLowerCase();
                final String cityText = (decoded['city'] as String? ?? '').toLowerCase();
                final String stateText = (googleState ?? '').toLowerCase();

                bool containsBlacklisted = false;
                for (final term in _blacklistedMunicipalities) {
                  if (streetText.contains(term) ||
                      suburbText.contains(term) ||
                      cityText.contains(term) ||
                      stateText.contains(term)) {
                    containsBlacklisted = true;
                    break;
                  }
                }

                if (lat != null && lng != null && (!isCoordsInCDMX || !isStateCDMX || !isZipCDMX || containsBlacklisted)) {
                  setState(() {
                    _cdmxBoundaryError = "La dirección seleccionada está fuera de la Ciudad de México. Ohtli por ahora solo opera dentro de la CDMX.";
                    _streetController.text = '';
                    _suburbController.text = '';
                    _zipController.text = '';
                    _cityController.text = '';
                    _selectedLat = null;
                    _selectedLng = null;
                    _googleState = null;
                  });
                } else {
                  setState(() {
                    _cdmxBoundaryError = null;
                    _streetController.text = decoded['street'] as String? ?? '';
                    _suburbController.text = decoded['suburb'] as String? ?? '';
                    _zipController.text = decoded['zip'] as String? ?? '';
                    _cityController.text = decoded['city'] as String? ?? '';
                    _stateController.text = 'Ciudad de México';
                    _countryController.text = 'México';
                    _selectedLat = lat;
                    _selectedLng = lng;
                    _googleState = googleState;
                    _autocompleteError = null;
                  });

                  if (lat != null && lng != null && globalContext.has('panOhtliAddressMapToLatLng')) {
                    globalContext.callMethodVarArgs('panOhtliAddressMapToLatLng'.toJS, <JSAny?>[(lat).jsify(), (lng).jsify()]);
                  }
                }
              }
            }
            setState(() => _isSearchingPredictions = false);
          })).toJS]);
      }
    } catch (e) {
      print("Place details error: $e");
      setState(() {
        _autocompleteError = e.toString();
        _isSearchingPredictions = false;
      });
    }
  }

  Widget _buildMapPickerWidget(bool isMobile) {
    if (!kIsWeb) {
      return const SizedBox.shrink();
    }
    
    return Container(
      height: isMobile ? 260 : 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OhtliColors.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const HtmlElementView(viewType: 'ohtli-address-map'),
            
            IgnorePointer(
              child: Transform.translate(
                offset: const Offset(0, -22), 
                child: SvgPicture.asset(
                  'assets/pin.svg',
                  height: 44,
                ),
              ),
            ),
            
            Positioned(
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: OhtliColors.cloudDancer.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.touch_app_outlined, size: 14, color: OhtliColors.stormyTeal),
                    const SizedBox(width: 6),
                    Text(
                      'Mueve el mapa para poner el pin en la entrada',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: OhtliColors.onyx,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String categoryName, IconData icon) {
    final isSelected = _selectedCategory == categoryName;
    return ChoiceChip(
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? Colors.white : OhtliColors.subtleText,
      ),
      label: Text(
        categoryName,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? Colors.white : OhtliColors.onyx,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedCategory = categoryName);
      },
      selectedColor: OhtliColors.stormyTeal,
      backgroundColor: OhtliColors.cloudDancer,
      elevation: 0,
      pressElevation: 0,
      shape: StadiumBorder(
        side: BorderSide(color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder),
      ),
    );
  }

  /// Etiqueta arriba del campo (no dentro, donde se encimaba con el borde).
  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    IconData? icon,
    TextInputType? keyboardType,
    FormFieldValidator<String>? validator,
    ValueChanged<String>? onChanged,
    Iterable<String>? autofillHints,
  }) {
    OutlineInputBorder border(Color c, double w) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          onChanged: onChanged,
          autofillHints: autofillHints,
          style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14.5),
          cursorColor: OhtliColors.accentText,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.4), fontSize: 14.5),
            prefixIcon: icon == null ? null : Icon(icon, color: OhtliColors.accentText, size: 20),
            filled: true,
            fillColor: OhtliColors.cloudDancer,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: border(OhtliColors.cardBorder, 1),
            enabledBorder: border(OhtliColors.cardBorder, 1),
            focusedBorder: border(OhtliColors.accentText, 1.6),
            errorBorder: border(OhtliColors.xoconostle, 1.2),
            focusedErrorBorder: border(OhtliColors.xoconostle, 1.6),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
        ),
      );

  Widget _notice(String text, {IconData icon = Icons.info_outline_rounded}) {
    final color = OhtliSettings.instance.isDarkMode ? const Color(0xFFF2A3A3) : const Color(0xFFB3261E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx, height: 1.4)),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final bool isCoordsInCDMX = _isCoordinateInCDMX(_selectedLat, _selectedLng);
    final bool isStateCDMX = _isOfficialCDMX(_googleState);
    final bool isZipCDMX = _isValidCDMXZip(_zipController.text);

    final String streetText = _streetController.text.toLowerCase();
    final String suburbText = _suburbController.text.toLowerCase();
    final String cityText = _cityController.text.toLowerCase();

    bool containsBlacklisted = false;
    for (final term in _blacklistedMunicipalities) {
      if (streetText.contains(term) || suburbText.contains(term) || cityText.contains(term)) {
        containsBlacklisted = true;
        break;
      }
    }

    if (_selectedLat == null || _selectedLng == null) {
      setState(() => _cdmxBoundaryError = 'Busca la dirección o mueve el mapa para marcar dónde está.');
      return;
    }
    if (!isCoordsInCDMX || !isStateCDMX || !isZipCDMX || containsBlacklisted) {
      setState(() => _cdmxBoundaryError = 'Elige una dirección dentro de la Ciudad de México o mueve el pin.');
      return;
    }

    widget.onSave({
      'customName': _customNameController.text.trim(),
      'category': _selectedCategory,
      'street': _streetController.text.trim(),
      'suburb': _suburbController.text.trim(),
      'zip': _zipController.text.trim(),
      'city': _cityController.text.trim(),
      'state': 'Ciudad de México',
      'country': 'México',
      'lat': _selectedLat,
      'lng': _selectedLng,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.initialAddress == null;
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 900;
    final requiredText = (String msg) => (String? v) => v == null || v.trim().isEmpty ? msg : null;

    return Card(
      elevation: 0,
      color: OhtliColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 18 : 26),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isNew ? 'Nueva dirección' : 'Editar dirección',
                  style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: OhtliColors.onyx),
                ),
                const SizedBox(height: 4),
                Text(
                  'Úsala como punto de partida de tus rutas. Por ahora Ohtli funciona dentro de la CDMX.',
                  style: GoogleFonts.inter(fontSize: 13.5, height: 1.45, color: OhtliColors.subtleText),
                ),
                const SizedBox(height: 22),

                // 1. Buscar
                _field(
                  label: 'Busca la dirección',
                  controller: _searchController,
                  hint: 'Calle, número y colonia',
                  icon: Icons.search_rounded,
                  onChanged: _onAddressInputChanged,
                ),
                if (_isSearchingPredictions) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(minHeight: 2, color: OhtliColors.accentText, backgroundColor: Colors.transparent),
                ],
                if (_predictions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: OhtliColors.cloudDancer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: OhtliColors.cardBorder),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _predictions.length,
                      itemBuilder: (context, idx) {
                        final pred = _predictions[idx];
                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.location_on_outlined, color: OhtliColors.accentText, size: 18),
                          title: Text(
                            pred['description'] ?? '',
                            style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.onyx),
                          ),
                          onTap: () => _selectPrediction(pred),
                        );
                      },
                    ),
                  ),
                ],
                if (_autocompleteError != null) ...[
                  const SizedBox(height: 8),
                  _notice(
                    'No pudimos buscar direcciones en este momento. Mueve el mapa hasta el lugar o escribe los datos abajo.',
                    icon: Icons.wifi_off_rounded,
                  ),
                ],
                const SizedBox(height: 14),

                // 2. Mapa
                _buildMapPickerWidget(isMobile),
                if (_cdmxBoundaryError != null) ...[
                  const SizedBox(height: 12),
                  _notice(_cdmxBoundaryError!),
                ],
                const SizedBox(height: 24),

                // 3. Datos
                _sectionTitle('Datos de la dirección'),
                _field(
                  label: 'Calle y número',
                  controller: _streetController,
                  icon: Icons.signpost_outlined,
                  autofillHints: const [AutofillHints.streetAddressLine1],
                  validator: requiredText('Escribe la calle y el número.'),
                ),
                const SizedBox(height: 14),
                _field(
                  label: 'Colonia',
                  controller: _suburbController,
                  validator: requiredText('Escribe la colonia.'),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _field(
                        label: 'Código postal',
                        controller: _zipController,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.postalCode],
                        validator: requiredText('Falta el C.P.'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: _field(
                        label: 'Alcaldía',
                        controller: _cityController,
                        validator: requiredText('Falta la alcaldía.'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 4. Nombre y tipo
                _sectionTitle('¿Cómo la quieres llamar?'),
                _field(
                  label: 'Nombre (opcional)',
                  controller: _customNameController,
                  hint: 'Ej. Casa, Oficina, Hotel del viaje',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final trimmed = value.trim().toLowerCase();
                    if (widget.existingNames.map((e) => e.toLowerCase()).contains(trimmed)) {
                      return 'Ya tienes una dirección con este nombre.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildCategoryChip('Hogar', Icons.home_rounded),
                    _buildCategoryChip('Hotel', Icons.hotel_rounded),
                    _buildCategoryChip('Renta en app', Icons.vpn_key_rounded),
                    _buildCategoryChip('Familiar', Icons.family_restroom_rounded),
                    _buildCategoryChip('Amigos', Icons.group_rounded),
                    _buildCategoryChip('Otro', Icons.location_on_rounded),
                  ],
                ),
                const SizedBox(height: 28),

                // 5. Acciones
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: widget.onCancel,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: OhtliColors.onyx,
                            side: BorderSide(color: OhtliColors.onyx.withValues(alpha: 0.16)),
                            shape: const StadiumBorder(),
                            textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: OhtliColors.stormyTeal,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            textStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          child: Text(isNew ? 'Guardar dirección' : 'Guardar cambios'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
