import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:growell/Home/homeScreen.dart';
import 'package:growell/authfiles/PhoneAuthScreen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://lmqogledtugtltwyflho.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxtcW9nbGVkdHVndGx0d3lmbGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDI2NTkzNTYsImV4cCI6MjA1ODIzNTM1Nn0.8bs_jnJc7r4MW4YFZtNuczzCpIsusoX9SZ5IVrdKfkM',
  );

  runApp(const MyApp());
  // Handle location permission after app starts
  _handleLocationPermission();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: PhoneAuthScreen(),
    );
  }
}

// Function to handle location permission and fetch location
Future<void> _handleLocationPermission() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    debugPrint("Location services are disabled.");
    return;
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      debugPrint("Location permissions are denied.");
      return;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    debugPrint("Location permissions are permanently denied.");
    return;
  }

  // Fetch the user's current location
  Position position = await Geolocator.getCurrentPosition();
  debugPrint("Location: ${position.latitude}, ${position.longitude}");
}
