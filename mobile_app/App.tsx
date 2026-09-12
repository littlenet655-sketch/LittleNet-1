import { useEffect, useState } from 'react';
import { SafeAreaView, StatusBar, StyleSheet, Text, View } from 'react-native';
import { API_BASE_URL, apiRequest, routes } from './src/api/client';

type Health = {
  ok: boolean;
  client?: string;
  framework?: string;
  api_versions?: number[];
};

export default function App() {
  const [status, setStatus] = useState(API_BASE_URL ? 'Checking backend…' : 'Set EXPO_PUBLIC_API_BASE_URL');

  useEffect(() => {
    if (!API_BASE_URL) return;
    let active = true;
    apiRequest<Health>(routes.health)
      .then((result) => active && setStatus(result.ok ? 'Backend connected' : 'Backend not ready'))
      .catch(() => active && setStatus('Backend unavailable'));
    return () => {
      active = false;
    };
  }, []);

  return (
    <SafeAreaView style={styles.page}>
      <StatusBar barStyle="dark-content" />
      <View style={styles.card}>
        <Text style={styles.brand}>LittleNet</Text>
        <Text style={styles.title}>React Native mobile foundation</Text>
        <Text style={styles.body}>{status}</Text>
        <Text style={styles.note}>Replit should build the real Kids, Parent and Admin screens from this single app root.</Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  page: { flex: 1, backgroundColor: '#ffffff', justifyContent: 'center', padding: 24 },
  card: { borderWidth: 1, borderColor: '#e5e7eb', borderRadius: 24, padding: 24, gap: 10 },
  brand: { fontSize: 28, fontWeight: '800' },
  title: { fontSize: 20, fontWeight: '700' },
  body: { fontSize: 16 },
  note: { fontSize: 14, lineHeight: 20 },
});
