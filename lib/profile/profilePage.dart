import 'package:flutter/material.dart';
import 'package:growell/authfiles/PhoneAuthScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Profilepage extends StatefulWidget {
  const Profilepage({super.key});

  @override
  State<Profilepage> createState() => _ProfilepageState();
}

class _ProfilepageState extends State<Profilepage> {
  // Logout function
  Future<void> _logout() async {
    // Get SharedPreferences instance
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Set isLoggedIn to false
    await prefs.setBool('isLoggedIn', false);

    // Optional: Clear other stored data (e.g., phone number)
    await prefs.remove('phoneNumber');

    // Navigate back to the login or authentication screen
    // Replace `PhoneAuthScreen` with your actual login screen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => PhoneAuthScreen()),
    );// Use named routing or MaterialPageRoute
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Profile Page"),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: _logout, // Call the logout function
          child: Text("Log Out"),
        ),
      ),
    );
  }
}