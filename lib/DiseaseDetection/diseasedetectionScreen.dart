import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class DiseaseDetectionPage extends StatefulWidget {
  @override
  _DiseaseDetectionPageState createState() => _DiseaseDetectionPageState();
}

class _DiseaseDetectionPageState extends State<DiseaseDetectionPage> {
  File? _image;
  final picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  Future<void> _discardImage() async {
    setState(() {
      _image = null;
    });
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
              : Image.file(_image!,height: 300,width: 300,),
          SizedBox(height: 20),
          _image == null ? 
          Row(
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
          ) : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(onPressed: (){
                //here we have to write the logic of  uploading image

              }, child: Text("Upload Image")),
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
