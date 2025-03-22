import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:growell/DiseaseDetection/diseaseDetailsPage.dart';
import 'package:growell/DiseaseDetection/predict_api.dart';
import 'package:image_picker/image_picker.dart';

class DiseaseDetectionPage extends StatefulWidget {
  @override
  _DiseaseDetectionPageState createState() => _DiseaseDetectionPageState();
}

class _DiseaseDetectionPageState extends State<DiseaseDetectionPage> {
  File? _image;
  String? _base64Image;
  bool _isLoading = false;
  final picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      File imageFile = File(pickedFile.path);
      List<int> imageBytes = await imageFile.readAsBytes();
      String base64String = base64Encode(imageBytes);

      setState(() {
        _image = imageFile;
        _base64Image = base64String;
      });
    }
  }

  Future<void> _discardImage() async {
    setState(() {
      _image = null;
      _base64Image = null;
    });
  }

  Future<void> PredictDisease(String? ImgPath) async {
    setState(() {
      _isLoading = true;
    });

    Map<String, dynamic>? res = await predict(ImgPath);

    setState(() {
      _isLoading = false;
    });

    if (res != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => Diseasedetailspage(res: res)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Disease Detection')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _image == null
              ? Text('No image selected', style: TextStyle(fontSize: 18))
              : Image.file(_image!, height: 300, width: 300),
          SizedBox(height: 20),
          _image == null
              ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildNeonButton(
                text: 'Capture Image',
                onPressed: () => _pickImage(ImageSource.camera),
                color: Colors.blue,
              ),
              SizedBox(width: 20),
              _buildNeonButton(
                text: 'Pick from Gallery',
                onPressed: () => _pickImage(ImageSource.gallery),
                color: Colors.green,
              ),
            ],
          )
              : _isLoading
              ? CircularProgressIndicator()
              : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildNeonButton(
                text: 'Upload Image',
                onPressed: () async {
                  await PredictDisease(_base64Image);
                },
                color: Colors.purple,
              ),
              SizedBox(width: 20),
              _buildNeonButton(
                text: 'Discard Image',
                onPressed: () => _discardImage(),
                color: Colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNeonButton({required String text, required VoidCallback onPressed, required Color color}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        backgroundColor: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        shadowColor: color.withOpacity(0.5),
        elevation: 10,
      ),
      child: Text(text, style: TextStyle(color: Colors.white)),
    );
  }
}
