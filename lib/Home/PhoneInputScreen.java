import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:growell/authfiles/otpverification.dart';

class PhoneInputScreen extends StatefulWidget {
  @override
  _PhoneInputScreenState createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends State<PhoneInputScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _phoneController = TextEditingController();
  bool _isChecked = false;

  Future<void> _verifyPhoneNumber() async {
    if (_phoneController.text.isEmpty || !_isChecked) {
      _showSnackBar('Please enter your phone number and accept terms.');
      return;
    }
    
    await _auth.verifyPhoneNumber(
      phoneNumber: _phoneController.text,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
        _showSnackBar('Authentication successful!');
      },
      verificationFailed: (FirebaseAuthException e) {
        _showSnackBar('Verification failed: ${e.message}');
      },
      codeSent: (String verificationId, int? resendToken) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtpVerificationScreen(verificationId: verificationId),
          ),
        );
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
      timeout: Duration(seconds: 60),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Log in to JioKrishi.',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24),
            Text('Mobile number', style: TextStyle(fontSize: 16)),
            TextField(
              controller: _phoneController,
              decoration: InputDecoration(
                hintText: 'Enter your mobile number',
                border: UnderlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            SizedBox(height: 24),
            Row(
              children: [
                Checkbox(
                  value: _isChecked,
                  onChanged: (bool? value) {
                    setState(() {
                      _isChecked = value ?? false;
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    'By continuing, you agree to JioKrishi’s Terms & Conditions and Privacy Policy',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _verifyPhoneNumber,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isChecked ? Colors.green : Colors.grey,
                minimumSize: Size(double.infinity, 50),
              ),
              child: Text('Send OTP', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
