import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart'; // For formatting dates

class FarmDetailsPage extends StatefulWidget {
  final Map<String, dynamic> farm;

  const FarmDetailsPage({super.key, required this.farm});

  @override
  State<FarmDetailsPage> createState() => _FarmDetailsPageState();
}

class _FarmDetailsPageState extends State<FarmDetailsPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> moistureData = [];
  bool isLoading = true;
  String? errorMessage;
  late RealtimeChannel _moistureChannel;
  late RealtimeChannel _alertChannel;

  // State to manage the alert button's waiting state
  bool _isAlerting = false;
  String? _alertingDeviceId; // To track which device is being alerted

  @override
  void initState() {
    super.initState();
    _fetchMoistureData(); // Fetch initial data
    _setupRealtimeMoistureListener(); // Set up real-time listener for moisture data
    _setupRealtimeAlertListener(); // Set up real-time listener for alert status
  }

  @override
  void dispose() {
    _moistureChannel.unsubscribe();
    _alertChannel.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchMoistureData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final String farmId = widget.farm['id'].toString();
      print("Fetching initial moisture data for Farm_ID: $farmId");

      final response = await supabase
          .from('moisture_data')
          .select()
          .eq('Farm_ID', farmId)
          .order('created_at', ascending: false)
          .limit(10);

      if (response.isNotEmpty) {
        setState(() {
          moistureData = List<Map<String, dynamic>>.from(response);
          isLoading = false;
        });
        print("Fetched initial moisture data: $moistureData");
      } else {
        setState(() {
          errorMessage = "No moisture data found for this farm.";
          isLoading = false;
        });
        print("No data found in moisture_data response: $response");
      }
    } on PostgrestException catch (e) {
      setState(() {
        errorMessage = "Error fetching initial moisture data: ${e.message}";
        isLoading = false;
      });
      print("Supabase error fetching initial moisture data: ${e.message}");
    } catch (e) {
      setState(() {
        errorMessage = "An unexpected error occurred: $e";
        isLoading = false;
      });
      print("Unexpected exception caught while fetching initial moisture data: $e");
    }
  }

  void _setupRealtimeMoistureListener() {
    final String farmId = widget.farm['id'].toString();
    _moistureChannel = supabase.channel('moisture_data_channel_$farmId');

    _moistureChannel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'moisture_data',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'Farm_ID',
        value: farmId,
      ),
      callback: (payload) {
        print('Realtime moisture INSERT received: ${payload.newRecord}');
        final newData = payload.newRecord;
        if (newData != null) {
          setState(() {
            // Remove error message if data starts flowing
            errorMessage = null;
            // Ensure moistureData is not null, initialize if necessary
            if (moistureData == null) {
              moistureData = [];
            }
            moistureData.insert(0, newData);
            if (moistureData.length > 10) {
              moistureData.removeLast();
            }
          });
        }
      },
    ).subscribe();
  }

  void _setupRealtimeAlertListener() {
    final String farmId = widget.farm['id'].toString();
    _alertChannel = supabase.channel('moisture_alert_channel_$farmId');

    _alertChannel.onPostgresChanges(
      event: PostgresChangeEvent.all, // Listen for all events (INSERT, UPDATE, DELETE)
      schema: 'public',
      table: 'moisture_alert',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'Farm_ID',
        value: farmId,
      ),
      callback: (payload) {
        print('--- Realtime alert update received ---');
        print('Event type: ${payload.eventType}');
        print('Old record: ${payload.oldRecord}');
        print('New record: ${payload.newRecord}');

        final Map<String, dynamic>? data;

        // Prioritize newRecord for updates, oldRecord for deletes, else take from newRecord
        if (payload.eventType == PostgresChangeEvent.update) {
          data = payload.newRecord;
        } else if (payload.eventType == PostgresChangeEvent.delete) {
          data = payload.oldRecord;
        } else { // For insert or if newRecord is directly available
          data = payload.newRecord ?? payload.oldRecord;
        }

        if (data != null) {
          final String receivedDeviceId = data['Device_ID']?.toString() ?? 'N/A';
          final bool receivedToAlert = data['toAlert'] ?? false;

          print('Received Device_ID: $receivedDeviceId, toAlert: $receivedToAlert');
          print('Current _alertingDeviceId: $_alertingDeviceId, _isAlerting: $_isAlerting');

          if (_alertingDeviceId != null && receivedDeviceId == _alertingDeviceId) {
            // Only update if the received alert is for the device we're currently alerting
            setState(() {
              _isAlerting = receivedToAlert;
              if (!_isAlerting) {
                // If 'toAlert' becomes false, it means the device acknowledged
                _alertingDeviceId = null; // Clear the device ID
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Device acknowledged the alert!")),
                );
                print('Alert acknowledged for device: $receivedDeviceId');
              } else {
                print('Alert remains active for device: $receivedDeviceId');
              }
            });
          } else {
            print('Received alert for a different device or no active alert: $receivedDeviceId');
          }
        } else {
          print('Payload data is null in alert callback.');
        }
      },
    ).subscribe();
  }

  Future<void> _toggleAlert(String deviceId) async {
    // Only attempt to toggle if not already in an alerting state for this device
    if (_isAlerting && _alertingDeviceId == deviceId) {
      print('Already in alerting state for this device: $deviceId');
      return;
    }

    setState(() {
      _isAlerting = true;
      _alertingDeviceId = deviceId;
    });

    try {
      final String farmId = widget.farm['id'].toString();
      final List<Map<String, dynamic>> existingAlerts = await supabase
          .from('moisture_alert')
          .select()
          .eq('Farm_ID', farmId)
          .eq('Device_ID', deviceId)
          .limit(1);

      if (existingAlerts.isNotEmpty) {
        await supabase
            .from('moisture_alert')
            .update({'toAlert': true})
            .eq('Farm_ID', farmId)
            .eq('Device_ID', deviceId);
        print('Updated existing alert for Device_ID: $deviceId');
      } else {
        await supabase.from('moisture_alert').insert({
          'Farm_ID': farmId,
          'Device_ID': deviceId,
          'toAlert': true,
          'created_at': DateTime.now().toIso8601String(), // Add created_at for new inserts
        });
        print('Inserted new alert for Device_ID: $deviceId');
      }
    } on PostgrestException catch (e) {
      print("Supabase error setting alert: ${e.message}");
      setState(() {
        _isAlerting = false; // Revert state if error occurs
        _alertingDeviceId = null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send alert: ${e.message}")),
        );
      });
    } catch (e) {
      print("Unexpected error setting alert: $e");
      setState(() {
        _isAlerting = false; // Revert state if error occurs
        _alertingDeviceId = null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send alert: $e")),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.farm['name'] ?? 'Farm Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchMoistureData, // Call the fetch method on refresh
            tooltip: 'Refresh Moisture Data',
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
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Crop: ${widget.farm['crop_name'] ?? 'N/A'}",
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              "Size: ${widget.farm['size'] ?? 'N/A'} acres",
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              "Coordinates: ${widget.farm['latitude'] ?? 'N/A'}, ${widget.farm['longitude'] ?? 'N/A'}",
              style: const TextStyle(fontSize: 18),
            ),
            const Divider(height: 40),

            // Moisture Data Section
            const Text(
              "Recent Moisture Readings:",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
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
                ? const Center(child: Text("No recent moisture data available."))
                : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: moistureData.length,
              itemBuilder: (context, index) {
                final data = moistureData[index];
                final DateTime createdAt = DateTime.parse(data['created_at']);
                final String formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(createdAt);
                final String deviceId = data['Device_ID'] ?? 'N/A';

                // Determine if this specific card should show "waiting"
                bool isCurrentDeviceAlerting = _isAlerting && _alertingDeviceId == deviceId;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  color: isCurrentDeviceAlerting ? Colors.amber[50] : null, // Highlight if alerting
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Value: ${data['value'] ?? 'N/A'}%",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Text("Device ID: $deviceId"),
                        Text("Recorded At: $formattedDate"),
                        const SizedBox(height: 10),
                        Center(
                          child: isCurrentDeviceAlerting
                              ? Column(
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 5),
                              Text("Waiting for $deviceId to acknowledge...",
                                style: const TextStyle(color: Colors.orange),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          )
                              : ElevatedButton.icon(
                            onPressed: () => _toggleAlert(deviceId),
                            icon: const Icon(Icons.notifications_active),
                            label: const Text("Alert Device"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}