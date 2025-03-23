import 'package:flutter/material.dart';
import 'package:growell/Home/homeScreen.dart';
import 'package:growell/authfiles/PhoneAuthScreen.dart';
import 'package:growell/authfiles/phoneInput.dart';
import 'package:firebase_core/firebase_core.dart';
// Import Firebase Core
import 'package:supabase_flutter/supabase_flutter.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://lmqogledtugtltwyflho.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxtcW9nbGVkdHVndGx0d3lmbGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDI2NTkzNTYsImV4cCI6MjA1ODIzNTM1Nn0.8bs_jnJc7r4MW4YFZtNuczzCpIsusoX9SZ5IVrdKfkM',
  );
  runApp(MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: PhoneAuthScreen(),
    );
  }
}
