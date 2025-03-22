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

    print("PredictDisease function called");
    Map<String, dynamic>? res = await predict(ImgPath);

    setState(() {
      _isLoading = false;
    });

    if (res != null) {
      print("Prediction Response: $res");
      if (res.containsKey("disease_name")) {
        String disease = res["disease_name"];
        print("Detected Disease: $disease");
      }
      //now we will move to the navigation page and see the details of the disease
      Navigator.push(context, MaterialPageRoute(builder: (context) => Diseasedetailspage(res: res,)));
    } else {
      print("No valid response received.");
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
              ElevatedButton(
                onPressed: () => _pickImage(ImageSource.camera),
                child: Text('Capture Image'),
              ),
              SizedBox(width: 20),
              ElevatedButton(
                onPressed: () => _pickImage(ImageSource.gallery),
                child: Text('Pick from Gallery'),
              ),
            ],
          )
              : _isLoading
              ? CircularProgressIndicator()
              : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () async {
                  await PredictDisease(_base64Image);
                },
                child: Text("Upload Image"),
              ),
              SizedBox(width: 20),
              ElevatedButton(
                onPressed: () => _discardImage(),
                child: Text('Discard Image'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
