import 'package:flutter/material.dart';

class Diseasedetailspage extends StatefulWidget {
  final Map<String, dynamic>? res;
  const Diseasedetailspage({super.key, required this.res});

  @override
  State<Diseasedetailspage> createState() => _DiseasedetailspageState();
}

class _DiseasedetailspageState extends State<Diseasedetailspage> {
  @override
  Widget build(BuildContext context) {
    final result = widget.res;
    final imageUrl = result?['input']?['images']?[0] ?? '';
    final disease = result?['result']?['disease']?['suggestions']?[0];
    final diseaseName = disease?['name'] ?? 'Unknown';
    final probability = disease?['probability'] ?? 0.0;
    final scientificName = disease?['scientific_name'] ?? 'Unknown';

    return Scaffold(
      appBar: AppBar(title: Text('Disease Details')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            imageUrl.isNotEmpty
                ? Image.network(imageUrl, height: 250, width: double.infinity, fit: BoxFit.cover)
                : SizedBox(height: 250, child: Center(child: Text('No Image Available'))),
            SizedBox(height: 20),
            Text('Disease: $diseaseName', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text('Scientific Name: $scientificName', style: TextStyle(fontSize: 18)),
            SizedBox(height: 10),
            Text('Probability: ${(probability * 100).toStringAsFixed(2)}%', style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}