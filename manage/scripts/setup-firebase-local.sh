#!/bin/bash
# Setup Firebase local development config
# Run this script after getting your new Firebase API key

echo "Setting up Firebase local config..."

if [ -f "web/firebase-config.local.js" ]; then
    echo "web/firebase-config.local.js already exists"
    echo "Edit it manually with your new API key"
    exit 0
fi

read -p "Enter your Firebase API Key: " API_KEY

cat > web/firebase-config.local.js << EOF
// Firebase configuration for local development
// This file is gitignored - do not commit!

window.FIREBASE_CONFIG = {
  apiKey: "$API_KEY",
  authDomain: "manage-d26fa.firebaseapp.com",
  projectId: "manage-d26fa",
  storageBucket: "manage-d26fa.firebasestorage.app",
  messagingSenderId: "9586444640",
  appId: "1:9586444640:web:25c7a53681520a44767605",
  measurementId: "G-2ZKDJEL95W"
};
EOF

echo "Created web/firebase-config.local.js"
echo "You can now run: flutter run -d chrome"
