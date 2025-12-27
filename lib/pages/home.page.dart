import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(onPressed: () {}, icon: Icon(Icons.home))
        ],
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Column(
          children: [
            SizedBox(width: 250, child: Image.asset('assets/home.png'),),
            Text('Welcome home!', style: Theme.of(context).textTheme.displaySmall,),
            FilledButton.tonal(onPressed: () {}, child: Text('Button'))
          ],
        ),
      ),
    );
  }
}