import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart'; // For formatting dates
import 'package:http/http.dart' as http; // Import the http package
import 'dart:convert'; // For JSON encoding/decoding

class FarmDetailsPage extends StatefulWidget {
  final Map<String, dynamic> farm;

  const FarmDetailsPage({super.key, required this.farm});

  @override
  State<FarmDetailsPage> createState() => _FarmDetailsPageState();
}

class _FarmDetailsPageState extends State<FarmDetailsPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> moistureData = []; // This will hold all relevant data
  bool isLoading = true;
  String? errorMessage;
  late RealtimeChannel _moistureDataChannel; // Single channel for moisture_data

  // State to manage the alert button's waiting state for each device
  Map<String, bool> _deviceAlertStatus = {}; // deviceId -> true if toAlert is active

  // State to track if an alert *send* action is in progress for a specific device
  Map<String, bool> _isSendingAlert = {}; // deviceId -> true if button pressed and waiting

  // State to hold the fetched CropDays for the current farm
  int? _farmCropDays;

  // OpenWeatherMap API Key (Replace with your actual key)
  final String _openWeatherApiKey = '22aca1ecdc2412673b8987880423fe52'; // <<< IMPORTANT: Replace this

  // Local Python API Endpoint (Replace with your local machine's IP and port)
  final String _localApiUrl = 'https://irrigation-prediction-api-latest.onrender.com/predict'; // <<< IMPORTANT: Replace this

  // Store combined data (moisture + weather + irrigation prediction) for display
  List<Map<String, dynamic>> _combinedDeviceData = [];
  bool _isProcessingWeatherData = false;


  @override
  void initState() {
    super.initState();
    print('DEBUG: initState called.');
    _fetchFarmDataAndMoisture(); // Fetch initial data including CropDays
    _setupRealtimeMoistureDataListener(); // Set up real-time listener for moisture data and alerts
  }

  @override
  void dispose() {
    print('DEBUG: dispose called. Unsubscribing from moisture data channel.');
    _moistureDataChannel.unsubscribe();
    super.dispose();
  }

  // New combined fetch method
  Future<void> _fetchFarmDataAndMoisture() async {
    print('DEBUG: _fetchFarmDataAndMoisture started.');
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final int farmId = widget.farm['id'] as int;
      final String cropName = widget.farm['crop_name'] ?? '';
      print("DEBUG: Fetching data for Farm_ID: $farmId, Crop: $cropName");

      // 1. Fetch CropDays first
      print('DEBUG: Calling _fetchFarmCropDays...');
      await _fetchFarmCropDays(farmId, cropName);
      print('DEBUG: _fetchFarmCropDays completed. _farmCropDays: $_farmCropDays');

      // 2. Then fetch moisture data
      print('DEBUG: Fetching moisture_data from Supabase...');
      final response = await supabase
          .from('moisture_data')
          .select()
          .eq('Farm_ID', farmId)
          .order('updated_at', ascending: false);

      print('DEBUG: Supabase moisture_data response received.');
      if (response.isNotEmpty) {
        setState(() {
          moistureData = List<Map<String, dynamic>>.from(response);
          isLoading = false;
          // Initialize alert status map
          for (var data in moistureData) {
            final String deviceId = data['Device_ID']?.toString() ?? '';
            if (deviceId.isNotEmpty) {
              _deviceAlertStatus[deviceId] = data['toAlert'] ?? false;
            }
          }
        });
        print("DEBUG: Fetched initial moisture data: ${moistureData.length} records.");
        // After fetching moisture data, fetch weather and send to local API
        print('DEBUG: Calling _fetchWeatherDataAndSendToLocalAPI...');
        _fetchWeatherDataAndSendToLocalAPI();
      } else {
        setState(() {
          errorMessage = "No moisture data found for this farm.";
          isLoading = false;
        });
        print("DEBUG: No data found in moisture_data response for Farm_ID $farmId.");
      }
    } on PostgrestException catch (e) {
      setState(() {
        errorMessage = "Error fetching farm data: ${e.message}";
        isLoading = false;
      });
      print("DEBUG ERROR: Supabase error fetching farm data: ${e.message}");
    } catch (e) {
      setState(() {
        errorMessage = "An unexpected error occurred: $e";
        isLoading = false;
      });
      print("DEBUG ERROR: Unexpected exception caught while fetching farm data: $e");
    }
  }

  Future<void> _fetchFarmCropDays(int farmId, String cropName) async {
    print('DEBUG: _fetchFarmCropDays started for Farm_ID: $farmId, Crop: $cropName');
    try {
      // Fetch from FarmsWithCropDays table
      final cropDaysResponse = await supabase
          .from('FarmsWithCropDays')
          .select('cropdays') // Assuming the column name is 'cropdays'
          .eq('id', farmId)
          .eq('crop_name', cropName) // Assuming CropType is also used to filter in this table
          .maybeSingle(); // Use maybeSingle for robust handling of no results

      if (cropDaysResponse != null && cropDaysResponse['cropdays'] is int) {
        setState(() {
          _farmCropDays = cropDaysResponse['cropdays'] as int;
        });
        print("DEBUG: Fetched CropDays: $_farmCropDays");
      } else {
        print("DEBUG: No CropDays found for Farm_ID $farmId and CropType $cropName. Setting to null.");
        setState(() {
          _farmCropDays = null;
        });
      }
    } on PostgrestException catch (e) {
      print("DEBUG ERROR: Supabase error fetching CropDays: ${e.message}");
      setState(() {
        _farmCropDays = null; // Indicate error or no data
      });
    } catch (e) {
      print("DEBUG ERROR: Unexpected error fetching CropDays: $e");
      setState(() {
        _farmCropDays = null; // Indicate error or no data
      });
    }
    print('DEBUG: _fetchFarmCropDays finished.');
  }

  void _setupRealtimeMoistureDataListener() {
    final int farmId = widget.farm['id'] as int;
    _moistureDataChannel = supabase.channel('moisture_data_channel_$farmId');
    print('DEBUG: Setting up Realtime listener for Farm_ID: $farmId.');

    _moistureDataChannel.onPostgresChanges(
      event: PostgresChangeEvent.all, // Listen for all events (INSERT, UPDATE)
      schema: 'public',
      table: 'moisture_data',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'Farm_ID',
        value: farmId,
      ),
      callback: (payload) {
        print('DEBUG: --- Realtime moisture_data change received ---');
        print('DEBUG: Event type: ${payload.eventType}');
        print('DEBUG: Old record: ${payload.oldRecord}');
        print('DEBUG: New record: ${payload.newRecord}');

        final newRecord = payload.newRecord;
        final oldRecord = payload.oldRecord;

        if (newRecord != null) {
          final String receivedDeviceId = newRecord['Device_ID']?.toString() ?? '';
          final bool newToAlertStatus = newRecord['toAlert'] ?? false;
          print('DEBUG: Realtime update for Device_ID: $receivedDeviceId, New toAlert: $newToAlertStatus');

          setState(() {
            errorMessage = null; // Clear error message on data update

            int existingIndex = moistureData.indexWhere((item) =>
            item['Device_ID'] == receivedDeviceId);

            if (existingIndex != -1) {
              moistureData[existingIndex] = newRecord;
              print('DEBUG: Updated existing moistureData record for $receivedDeviceId.');
            } else {
              moistureData.insert(0, newRecord);
              moistureData.sort((a, b) => (b['updated_at'] as String).compareTo(a['updated_at'] as String));
              print('DEBUG: Inserted new moistureData record for $receivedDeviceId. List size: ${moistureData.length}');
            }

            if (receivedDeviceId.isNotEmpty) {
              final bool oldToAlertStatus = oldRecord?['toAlert'] ?? false;

              _deviceAlertStatus[receivedDeviceId] = newToAlertStatus;

              if (oldToAlertStatus == false && newToAlertStatus == true) {
                if (_isSendingAlert[receivedDeviceId] == true) {
                  _isSendingAlert.remove(receivedDeviceId);
                  print('DEBUG: Alert active on DB for $receivedDeviceId. Stopping sending loading.');
                }
              }
              if (oldToAlertStatus == true && newToAlertStatus == false) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$receivedDeviceId acknowledged the alert!")),
                );
                print('DEBUG: Alert acknowledged for device: $receivedDeviceId');
                _isSendingAlert.remove(receivedDeviceId);
              }
            }
          });
          print('DEBUG: Realtime update triggered _fetchWeatherDataAndSendToLocalAPI.');
          _fetchWeatherDataAndSendToLocalAPI();
        } else if (payload.eventType == PostgresChangeEvent.delete && oldRecord != null) {
          final String deletedDeviceId = oldRecord['Device_ID']?.toString() ?? '';
          setState(() {
            moistureData.removeWhere((item) => item['Device_ID'] == deletedDeviceId);
            _deviceAlertStatus.remove(deletedDeviceId);
            _isSendingAlert.remove(deletedDeviceId);
            _combinedDeviceData.removeWhere((item) => item['Device_ID'] == deletedDeviceId);
          });
          print('DEBUG: Device $deletedDeviceId record deleted from DB.');
        }
      },
    ).subscribe();
    print('DEBUG: Realtime listener subscribed.');
  }

  Future<List<Map<String, dynamic>>> _fetchWeatherForecast() async {
    final double? latitude = widget.farm['latitude'] as double?;
    final double? longitude = widget.farm['longitude'] as double?;

    if (latitude == null || longitude == null) {
      print("DEBUG: No coordinates, cannot fetch forecast.");
      return [];
    }

    try {
      final Uri forecastUri = Uri.parse(
        'https://api.openweathermap.org/data/2.5/forecast/daily'
            '?lat=$latitude&lon=$longitude&cnt=16&units=metric&appid=$_openWeatherApiKey',
      );

      final http.Response forecastResponse = await http.get(forecastUri);
      if (forecastResponse.statusCode == 200) {
        final data = json.decode(forecastResponse.body);

        List<Map<String, dynamic>> forecastList = [];
        for (var day in data['list']) {
          forecastList.add({
            'date': DateTime.fromMillisecondsSinceEpoch(day['dt'] * 1000, isUtc: true),
            'temp': day['temp']['day'].toDouble(),
            'humidity': day['humidity'],
            'weather': day['weather'][0]['description'],
            'rain': day.containsKey('rain') ? day['rain'].toDouble() : 0.0,
          });
        }
        return forecastList;
      } else {
        print("DEBUG ERROR: Forecast API failed. ${forecastResponse.body}");
        return [];
      }
    } catch (e) {
      print("DEBUG ERROR: Forecast fetch exception: $e");
      return [];
    }
  }


  Future<void> _toggleAlert(String deviceId) async {
    print('DEBUG: _toggleAlert called for device: $deviceId');
    if (_isSendingAlert[deviceId] == true) {
      print('DEBUG: Alert already sending for device: $deviceId. Skipping.');
      return;
    }

    setState(() {
      _isSendingAlert[deviceId] = true;
    });
    print('DEBUG: Set _isSendingAlert[$deviceId] to true.');

    try {
      final int farmId = widget.farm['id'] as int;
      print('DEBUG: Attempting to update toAlert for Device_ID: $deviceId, Farm_ID: $farmId');

      await supabase
          .from('moisture_data')
          .update({
        'toAlert': true,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('Farm_ID', farmId)
          .eq('Device_ID', deviceId);

      print('DEBUG: Supabase update successful for alert request for Device_ID: $deviceId.');

    } on PostgrestException catch (e) {
      print("DEBUG ERROR: Supabase error sending alert for $deviceId: ${e.message}");
      setState(() {
        _isSendingAlert[deviceId] = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send alert: ${e.message}")),
        );
      }); // Corrected: closing parenthesis for setState
    } catch (e) {
      print("DEBUG ERROR: Unexpected error sending alert for $deviceId: $e");
      setState(() {
        _isSendingAlert[deviceId] = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send alert: $e")),
        );
      }); // Corrected: closing parenthesis for setState
    }
  }

  Future<void> _fetchWeatherDataAndSendToLocalAPI() async {
    print('DEBUG: _fetchWeatherDataAndSendToLocalAPI started.');
    setState(() {
      _isProcessingWeatherData = true;
    });

    final double? latitude = widget.farm['latitude'] as double?;
    final double? longitude = widget.farm['longitude'] as double?;
    final String cropName = widget.farm['crop_name'] ?? 'Unknown';

    if (latitude == null || longitude == null) {
      print("DEBUG WARNING: Farm coordinates not available for weather fetching. Skipping weather/prediction.");
      setState(() {
        _isProcessingWeatherData = false;
      });
      return;
    }

    try {
      // 1. Fetch weather data from OpenWeatherMap
      final Uri weatherUri = Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?lat=$latitude&lon=$longitude&units=metric&appid=$_openWeatherApiKey');
      print('DEBUG: Fetching weather data from: $weatherUri');
      final http.Response weatherResponse = await http.get(weatherUri);
      print('DEBUG: Weather API response status: ${weatherResponse.statusCode}');

      if (weatherResponse.statusCode == 200) {
        final Map<String, dynamic> weatherData = json.decode(weatherResponse.body);
        final double temperature = weatherData['main']['temp']?.toDouble() ?? 0.0;
        final double humidity = weatherData['main']['humidity']?.toDouble() ?? 0.0;

        print("DEBUG: Fetched weather data: Temp: ${temperature}°C, Humidity: ${humidity}%");

        // 2. Prepare data for the local Python API for each device
        List<Map<String, dynamic>> newCombinedDeviceData = [];
        print('DEBUG: Preparing data for local Python API for ${moistureData.length} devices.');
        for (var deviceData in moistureData) {
          final String deviceId = deviceData['Device_ID']?.toString() ?? '';
          final int rawSoilMoisture = deviceData['value'] as int? ?? 0;

          print('DEBUG: Processing Device ID: $deviceId, Raw Moisture: $rawSoilMoisture');

          // Use the fetched _farmCropDays, or a default if not found/error
          final int cropDaysToSend = _farmCropDays ?? 0; // Use 0 as a fallback if _farmCropDays is null
          print('DEBUG: CropDays to send for $deviceId: $cropDaysToSend');

          final Map<String, dynamic> inputData = {
            'CropType': cropName,
            'CropDays': cropDaysToSend,
            'SoilMoisture': rawSoilMoisture,
            'temperature': temperature,
            'Humidity': humidity,
          };
          print('DEBUG: Sending input data to local API for $deviceId: ${jsonEncode(inputData)}');

          // 3. Send data to local Python API
          final http.Response localApiResponse = await http.post(
            Uri.parse(_localApiUrl),
            headers: <String, String>{
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: jsonEncode(inputData),
          );
          print('DEBUG: Local API response status for $deviceId: ${localApiResponse.statusCode}');
          print('DEBUG: Local API response body for $deviceId: ${localApiResponse.body}'); // Add this for full response

          if (localApiResponse.statusCode == 200) {
            final Map<String, dynamic> predictionResponse = json.decode(localApiResponse.body);
            // Changed: Extract 'prediction' and convert to boolean (1 -> true, 0 -> false)
            final bool requiresIrrigation = (predictionResponse['prediction'] == 1);
            print("DEBUG: Local API prediction for $deviceId: ${predictionResponse['prediction']}. Irrigation required (boolean): $requiresIrrigation");

            newCombinedDeviceData.add({
              ...deviceData,
              'temperature': temperature,
              'humidity': humidity,
              'irrigation_required': requiresIrrigation, // Store the boolean directly
            });
          } else {
            print("DEBUG ERROR: Failed to send data to local API for $deviceId. Status: ${localApiResponse.statusCode}");
            print("DEBUG ERROR: Response body: ${localApiResponse.body}");
            newCombinedDeviceData.add({
              ...deviceData,
              'temperature': temperature,
              'humidity': humidity,
              'irrigation_required_error': 'Failed to get prediction (${localApiResponse.statusCode})',
            });
          }
        }
        setState(() {
          _combinedDeviceData = newCombinedDeviceData;
          _isProcessingWeatherData = false;
        });
        print('DEBUG: _combinedDeviceData updated. Processed ${newCombinedDeviceData.length} devices.');

      } else {
        print("DEBUG ERROR: Failed to fetch weather data. Status: ${weatherResponse.statusCode}");
        print("DEBUG ERROR: Weather response body: ${weatherResponse.body}");
        setState(() {
          errorMessage = "Failed to fetch weather data: ${weatherResponse.body}";
          _isProcessingWeatherData = false;
        });
      }
    } catch (e) {
      print("DEBUG ERROR: Error fetching weather or sending to local API: $e");
      setState(() {
        errorMessage = "Error fetching weather or sending to local API: $e";
        _isProcessingWeatherData = false;
      });
    }
    print('DEBUG: _fetchWeatherDataAndSendToLocalAPI finished.');
  }


  @override
  Widget build(BuildContext context) {
    // print('DEBUG: build method called.'); // This can be too verbose, use sparingly.
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.farm['name'] ?? 'Farm Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchFarmDataAndMoisture,
            tooltip: 'Refresh All Data',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Farm Image
            if (widget.farm['imageUrl'] != null && widget.farm['imageUrl'].isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.network(
                  widget.farm['imageUrl'],
                  height: 250,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 250,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: const Icon(Icons.broken_image, size: 100, color: Colors.grey),
                  ),
                ),
              )
            else
              Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: const Icon(Icons.eco, size: 100, color: Colors.grey),
              ),
            const SizedBox(height: 20),

            // Farm General Details
            Text(
              "Farm Name: ${widget.farm['name'] ?? 'N/A'}",
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const SizedBox(height: 8),
            Text(
              "Crop: ${widget.farm['crop_name'] ?? 'N/A'}",
              style: TextStyle(fontSize: 18, color: Colors.grey[800]),
            ),
            const SizedBox(height: 5),
            Text(
              "Size: ${widget.farm['size'] ?? 'N/A'} acres",
              style: TextStyle(fontSize: 18, color: Colors.grey[800]),
            ),
            const SizedBox(height: 5),
            Text(
              "Crop Days: ${_farmCropDays?.toString() ?? 'N/A'}", // Display fetched Crop Days
              style: TextStyle(fontSize: 18, color: Colors.grey[800]),
            ),
            const SizedBox(height: 5),
            Text(
              "Coordinates: ${widget.farm['latitude']?.toStringAsFixed(4) ?? 'N/A'}, ${widget.farm['longitude']?.toStringAsFixed(4) ?? 'N/A'}",
              style: TextStyle(fontSize: 18, color: Colors.grey[800]),
            ),
            const Divider(height: 40, thickness: 1.5, color: Colors.lightGreen),

            // Moisture Data Section
            const Text(
              "Recent Device Status:",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const SizedBox(height: 15),
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                ? Center(
              child: Text(
                errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 16),
              ),
            )
                : moistureData.isEmpty
                ? const Center(child: Text("No device data available for this farm.", style: TextStyle(fontSize: 16, color: Colors.grey)))
                : Column(
              children: [
                if (_isProcessingWeatherData)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2),
                        SizedBox(width: 10),
                        Text("Processing weather & irrigation data...", style: TextStyle(color: Colors.blueGrey)),
                      ],
                    ),
                  ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _combinedDeviceData.length, // Use combined data here
                  itemBuilder: (context, index) {
                    final data = _combinedDeviceData[index]; // Use combined data
                    final String deviceId = data['Device_ID']?.toString() ?? 'N/A';
                    final DateTime? updatedAt = data['updated_at'] != null
                        ? DateTime.parse(data['updated_at'])
                        : null;
                    final String formattedDate = updatedAt != null
                        ? DateFormat('MMM d, yyyy HH:mm:ss').format(updatedAt.toLocal())
                        : 'N/A';
                    final int rawMoistureValue = data['value'] as int? ?? -1; // Original value from DB
                    final bool isAlertActiveInDB = _deviceAlertStatus[deviceId] ?? false;
                    final bool isSendingAlert = _isSendingAlert[deviceId] ?? false;
                    final double? temperature = data['temperature'] as double?;
                    final double? humidity = data['humidity'] as double?;
                    // Now directly using the boolean value stored in _combinedDeviceData
                    final bool? requiresIrrigation = data['irrigation_required'] as bool?;
                    final String? irrigationError = data['irrigation_required_error'] as String?;

                    // Determine highlight color based on active alert status and irrigation need
                    Color cardColor = Colors.white; // Default color
                    if (isAlertActiveInDB) {
                      cardColor = Colors.orange.shade50; // Priority for active alert
                    } else if (requiresIrrigation == true) { // If prediction was 1
                      cardColor = Colors.red.shade50; // Light red if irrigation is needed
                    } else if (requiresIrrigation == false) { // If prediction was 0
                      cardColor = Colors.green.shade50; // Light green if no irrigation is needed
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      color: cardColor,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Device ID: $deviceId",
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                            ),
                            const SizedBox(height: 10),
                            _buildInfoRow(Icons.water_drop, "Moisture Reading:", "$rawMoistureValue (0-4095 raw ADC)"),
                            _buildInfoRow(Icons.access_time, "Last Updated:", formattedDate),
                            _buildInfoRow(Icons.thermostat, "Temperature:", "${temperature?.toStringAsFixed(1) ?? 'N/A'}°C"),
                            _buildInfoRow(Icons.opacity, "Humidity:", "${humidity?.toStringAsFixed(1) ?? 'N/A'}%"),
                            const SizedBox(height: 15),
                            if (requiresIrrigation != null)
                              Row(
                                children: [
                                  Icon(requiresIrrigation == true ? Icons.waves : Icons.check_circle_outline,
                                      color: requiresIrrigation == true ? Colors.red : Colors.green, size: 24),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Irrigation Needed: ${requiresIrrigation == true ? 'YES' : 'NO'}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: requiresIrrigation == true ? Colors.red : Colors.green[800],
                                    ),
                                  ),
                                ],
                              )
                            else if (irrigationError != null)
                              Row(
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.red, size: 24),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Irrigation Prediction: $irrigationError",
                                      style: const TextStyle(color: Colors.red, fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 15),
                            Center(
                              child: isSendingAlert
                                  ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(strokeWidth: 3),
                                  const SizedBox(height: 8),
                                  Text("Sending alert to $deviceId...",
                                      style: const TextStyle(color: Colors.orange, fontSize: 14)),
                                ],
                              )
                                  : isAlertActiveInDB // If alert is active in DB (device should be buzzing)
                                  ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.notifications_active, color: Colors.red, size: 40),
                                  const SizedBox(height: 5),
                                  const Text("Alert Active!",
                                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text("Waiting for $deviceId to acknowledge...",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                                ],
                              )
                                  : ElevatedButton.icon(
                                onPressed: () => _toggleAlert(deviceId),
                                icon: const Icon(Icons.notifications_active),
                                label: const Text("Alert Device"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const Text(
                  "16-Day Forecast:",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
                ),
                const SizedBox(height: 15),

                FutureBuilder(
                  future: _fetchWeatherForecast(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Text("No forecast data available.");
                    }

                    final forecast = snapshot.data!;
                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: forecast.length,
                      itemBuilder: (context, index) {
                        final day = forecast[index];
                        final formattedDate = DateFormat('MMM d, yyyy').format(day['date']);
                        final rain = day['rain'] > 0 ? "🌧️ Rain: ${day['rain']} mm" : "☀️ No rain";

                        return Card(
                          child: ListTile(
                            title: Text("$formattedDate - ${day['weather']}"),
                            subtitle: Text("Temp: ${day['temp']}°C | Humidity: ${day['humidity']}%\n$rain"),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey[600], size: 20),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}