import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' show promiseToFuture;
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
      if (kIsWeb && js.context.hasProperty('mountOhtliAddressMap')) {
        js.context.callMethod('mountOhtliAddressMap');
        
        final isNew = widget.initialAddress == null;
        if (isNew) {
          if (js.context.hasProperty('geocodeAndPanOhtliAddressMap')) {
            js.context.callMethod('geocodeAndPanOhtliAddressMap', ['Ciudad de México, México']);
          }
        } else {
          final lat = _selectedLat;
          final lng = _selectedLng;
          if (lat != null && lng != null && js.context.hasProperty('panOhtliAddressMapToLatLng')) {
            js.context.callMethod('panOhtliAddressMapToLatLng', [lat, lng]);
          } else {
            final fullAddr = "${_streetController.text}, ${_suburbController.text}, C.P. ${_zipController.text}, ${_cityController.text}, Ciudad de México, México";
            if (js.context.hasProperty('geocodeAndPanOhtliAddressMap')) {
              js.context.callMethod('geocodeAndPanOhtliAddressMap', [fullAddr]);
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
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _registerMapPlatformView() {
    if (kIsWeb && !_isOhtliMapPlatformViewRegistered) {
      ui_web.platformViewRegistry.registerViewFactory('ohtli-address-map', (int viewId) {
        final element = html.DivElement()
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
      js.context['ohtliMapCallback'] = js.allowInterop((String jsonStr) {
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
      });
    }
  }

  void _injectGooglePlacesApi() {
    if (!kIsWeb) return;
    const mapsApiKey = String.fromEnvironment('mapsApiKey');
    const apiKey = String.fromEnvironment('apiKey');
    final activeKey = mapsApiKey.isNotEmpty ? mapsApiKey : apiKey;
    if (activeKey.isEmpty) return;

    if (html.document.getElementById('google-maps-places-script') == null) {
      final script = html.ScriptElement()
        ..id = 'google-maps-places-script'
        ..src = 'https://maps.googleapis.com/maps/api/js?key=$activeKey&libraries=places&language=es&region=MX'
        ..async = true;
      html.document.head!.append(script);
    }

    if (html.document.getElementById('ohtli-places-helpers') == null || !js.context.hasProperty('getOhtliPlacePredictions')) {
      html.document.getElementById('ohtli-places-helpers')?.remove();

      final helpersScript = html.ScriptElement()
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

        window.mountOhtliAddressMap = function() {
          const checkExist = setInterval(function() {
            const mapDiv = document.getElementById('ohtli-map-container');
            if (mapDiv && window.google && window.google.maps) {
              clearInterval(checkExist);
              
              const defaultLatLng = { lat: 19.4326, lng: -99.1332 }; // CDMX
              const map = new google.maps.Map(mapDiv, {
                center: defaultLatLng,
                zoom: 15,
                disableDefaultUI: true,
                zoomControl: true,
                styles: ohtliMapStyles
              });
              
              window.ohtliCurrentMap = map;
              const geocoder = new google.maps.Geocoder();
              
              map.addListener('idle', () => {
                if (window.ohtliMapProgrammaticPanning) {
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
          if (!window.ohtliCurrentMap) return;
          window.ohtliMapProgrammaticPanning = true;
          window.ohtliCurrentMap.setCenter({ lat: lat, lng: lng });
          window.ohtliCurrentMap.setZoom(16);
          setTimeout(() => {
            window.ohtliMapProgrammaticPanning = false;
          }, 1000);
        };

        window.geocodeAndPanOhtliAddressMap = function(addressStr) {
          if (!window.google || !window.google.maps) return;
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
      html.document.head!.append(helpersScript);
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
        if (js.context.hasProperty('getOhtliPlacePredictions')) {
          js.context.callMethod('getOhtliPlacePredictions', [
            val,
            js.allowInterop((result) {
              if (result != null && mounted) {
                final String jsonStr = result as String;
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
            })
          ]);
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
      _isSearchingPredictions = true;
      _autocompleteError = null;
      _cdmxBoundaryError = null;
    });

    try {
      if (js.context.hasProperty('getOhtliPlaceDetails')) {
        js.context.callMethod('getOhtliPlaceDetails', [
          placeId,
          js.allowInterop((result) {
            if (result != null && mounted) {
              final String jsonStr = result as String;
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

                  if (lat != null && lng != null && js.context.hasProperty('panOhtliAddressMapToLatLng')) {
                    js.context.callMethod('panOhtliAddressMapToLatLng', [lat, lng]);
                  }
                }
              }
            }
            setState(() => _isSearchingPredictions = false);
          })
        ]);
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
      height: isMobile ? 240 : 340,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OhtliColors.cantera, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                  color: OhtliColors.cloudDancer.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
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
                      'Arrastra para ajustar posición',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
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
        color: isSelected ? Colors.white : OhtliColors.onyx.withOpacity(0.7),
      ),
      label: Text(
        categoryName,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? Colors.white : OhtliColors.onyx.withOpacity(0.8),
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedCategory = categoryName;
          });
        }
      },
      selectedColor: OhtliColors.stormyTeal,
      backgroundColor: OhtliColors.cloudDancer,
      elevation: 0,
      pressElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cantera.withOpacity(0.5),
          width: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.initialAddress == null;
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 900;

    return Card(
      elevation: 0,
      color: OhtliColors.inputBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Header Title
                Text(
                  isNew ? 'Nueva Dirección' : 'Editar Dirección',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx,
                  ),
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _customNameController,
                  style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final trimmed = value.trim().toLowerCase();
                    if (widget.existingNames.map((e) => e.toLowerCase()).contains(trimmed)) {
                      return 'Ya existe una dirección con este nombre';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'Nombre Personalizado (ej. Mi Casa, Oficina)',
                    labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.bookmark_outline_rounded, color: OhtliColors.stormyTeal, size: 20),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),

                // Categoría
                Text(
                  'Categoría',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 20),
                if (_cdmxBoundaryError != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: OhtliColors.xoconostle.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: OhtliColors.xoconostle.withOpacity(0.25), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: OhtliColors.xoconostle, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _cdmxBoundaryError!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: OhtliColors.xoconostle,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 2. Street Input
                TextFormField(
                  controller: _streetController,
                  style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                  onChanged: _onAddressInputChanged,
                  validator: (value) => value == null || value.trim().isEmpty ? 'Ingresa la calle y número' : null,
                  decoration: InputDecoration(
                    labelText: 'Calle y Número',
                    labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.home_outlined, color: OhtliColors.stormyTeal, size: 20),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),

                if (_autocompleteError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: OhtliColors.xoconostle.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: OhtliColors.xoconostle.withOpacity(0.25), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: OhtliColors.xoconostle, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Error de autocompletado: $_autocompleteError. Verifica que "Places API (Legacy)" esté habilitada en tu consola GCP y asociada a tu API Key.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: OhtliColors.xoconostle,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Autocomplete predictions dropdown
                if (_predictions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: OhtliColors.cloudDancer,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _predictions.length,
                      itemBuilder: (context, idx) {
                        final pred = _predictions[idx];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on_rounded, color: OhtliColors.stormyTeal, size: 16),
                          title: Text(
                            pred['description'] ?? '',
                            style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx),
                          ),
                          onTap: () => _selectPrediction(pred),
                        );
                      },
                    ),
                  ),
                ],
                if (_isSearchingPredictions) ...[
                  const SizedBox(height: 8),
                  const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: OhtliColors.stormyTeal),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // 3. Suburb Input
                TextFormField(
                  controller: _suburbController,
                  style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Ingresa la colonia o delegación' : null,
                  decoration: InputDecoration(
                    labelText: 'Colonia / Zona',
                    labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.map_outlined, color: OhtliColors.stormyTeal, size: 20),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Zip and City Inputs
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _zipController,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Requerido' : null,
                        decoration: InputDecoration(
                          labelText: 'Código Postal',
                          labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                          prefixIcon: const Icon(Icons.markunread_mailbox_outlined, color: OhtliColors.stormyTeal, size: 20),
                          filled: true,
                          fillColor: OhtliColors.cloudDancer,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _cityController,
                        style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Requerido' : null,
                        decoration: InputDecoration(
                          labelText: 'Ciudad / Delegación',
                          labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                          filled: true,
                          fillColor: OhtliColors.cloudDancer,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 5. State and Country (CDMX, México)
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stateController,
                        readOnly: true,
                        style: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.55), fontSize: 14),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Requerido' : null,
                        decoration: InputDecoration(
                          labelText: 'Estado (CDMX)',
                          labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.4)),
                          prefixIcon: const Icon(Icons.map_outlined, color: OhtliColors.stormyTeal, size: 20),
                          filled: true,
                          fillColor: OhtliColors.cloudDancer.withOpacity(0.6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _countryController,
                        readOnly: true,
                        style: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.55), fontSize: 14),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Requerido' : null,
                        decoration: InputDecoration(
                          labelText: 'País (México)',
                          labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.4)),
                          prefixIcon: const Icon(Icons.public_rounded, color: OhtliColors.stormyTeal, size: 20),
                          filled: true,
                          fillColor: OhtliColors.cloudDancer.withOpacity(0.6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 6. Map Section Title
                Text(
                  'Ubicación en Mapa',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx,
                  ),
                ),
                const SizedBox(height: 12),

                // 7. Full-width Map Widget
                _buildMapPickerWidget(isMobile),
                const SizedBox(height: 28),

                // 8. Form Actions
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: widget.onCancel,
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.6)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (!_formKey.currentState!.validate()) return;

                          final bool isCoordsInCDMX = _isCoordinateInCDMX(_selectedLat, _selectedLng);
                          final bool isStateCDMX = _isOfficialCDMX(_googleState);
                          final bool isZipCDMX = _isValidCDMXZip(_zipController.text);

                          final String streetText = _streetController.text.toLowerCase();
                          final String suburbText = _suburbController.text.toLowerCase();
                          final String cityText = _cityController.text.toLowerCase();

                          bool containsBlacklisted = false;
                          for (final term in _blacklistedMunicipalities) {
                            if (streetText.contains(term) ||
                                suburbText.contains(term) ||
                                cityText.contains(term)) {
                              containsBlacklisted = true;
                              break;
                            }
                          }

                          if (!isCoordsInCDMX || !isStateCDMX || !isZipCDMX || containsBlacklisted) {
                            setState(() {
                              _cdmxBoundaryError = "Por favor selecciona una dirección o mueve el pin dentro de la Ciudad de México.";
                            });
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
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OhtliColors.stormyTeal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: Text(
                          isNew ? 'Agregar' : 'Actualizar',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
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
