import { useEffect, useState } from 'react';
import { FlatList, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { fetchOwnProfile, updateOwnProfile } from '../../api/kidsProfiles';
import { blockUser, fetchConnections, fetchSaved, muteUser, submitReport, type PostDetail } from '../../api/kidsSocial';
import { useAuth } from '../../auth/AuthProvider';
import type { ChildScreenProps } from '../../navigation/types';
import { Avatar } from '../../ui/social';
import { Button, Card, EmptyState, ErrorState, Field, GateNotice, LoadingState, Notice, Screen } from '../../ui/components';
import { colors } from '../../ui/tokens';

type Person = { user_id?: number; child_id?: number; id?: number; full_name?: string; username?: string; avatar_url?: string | null };
const personId = (p: Person) => Number(p.user_id ?? p.child_id ?? p.id ?? 0);

export function SavedContentScreen({ navigation }: ChildScreenProps<'SavedContent'>) {
  const { session } = useAuth(); const [tab, setTab] = useState<'posts' | 'reels' | 'learning'>('posts');
  const [data, setData] = useState<{ posts: PostDetail[]; reels: PostDetail[] }>({ posts: [], reels: [] }); const [error, setError] = useState<unknown>(null);
  useEffect(() => { if (session) fetchSaved(session.token).then(setData).catch(setError); }, [session?.token]);
  if (error) return <Screen><GateNotice error={error} /><ErrorState message="Saved content is unavailable." /></Screen>;
  const list = tab === 'posts' ? data.posts : tab === 'reels' ? data.reels : data.posts.filter((p) => String(p.content_category ?? '').toLowerCase().includes('learn'));
  return <Screen><ScrollView><Text style={styles.heading}>Saved</Text><Text style={styles.sub}>Keep kind ideas close.</Text><View style={styles.tabs}>{(['posts', 'reels', 'learning'] as const).map((t) => <Pressable key={t} onPress={() => setTab(t)}><Text style={[styles.tab, tab === t && styles.active]}>{t === 'learning' ? 'LEARNING' : t.toUpperCase()}</Text></Pressable>)}</View>{!list.length ? <EmptyState title="Nothing saved yet" body="Tap Save on a post or reel to find it here." /> : list.map((p) => <Pressable key={p.post_id} onPress={() => navigation.navigate('PostDetail', { postId: p.post_id })}><Card><Text style={styles.body}>{p.caption || 'Saved post'}</Text></Card></Pressable>)}</ScrollView></Screen>;
}

export function EditProfileScreen({ navigation }: ChildScreenProps<'EditProfile'>) {
  const { session } = useAuth(); const [name, setName] = useState(''); const [bio, setBio] = useState(''); const [busy, setBusy] = useState(false); const [message, setMessage] = useState('');
  useEffect(() => { if (session) fetchOwnProfile(session.token).then((r) => { setName(String(r.profile.full_name ?? '')); setBio(String(r.profile.bio ?? '')); }).catch(() => setMessage('Could not load profile.')); }, [session?.token]);
  return <Screen><ScrollView keyboardShouldPersistTaps="handled"><Text style={styles.heading}>Edit profile</Text><Text style={styles.sub}>Share a little about yourself. Keep personal details private.</Text><Card><Field label="Name" value={name} onChangeText={setName} maxLength={60} /><Field label="Bio" value={bio} onChangeText={setBio} multiline maxLength={160} /><Notice tone="info" message="Interests are managed with your guardian for safety." />{message ? <Notice tone="ok" message={message} /> : null}<Button label={busy ? 'Saving…' : 'Save changes'} disabled={busy} onPress={() => { if (!session) return; setBusy(true); updateOwnProfile(session.token, { full_name: name.trim(), bio: bio.trim() }).then(() => setMessage('Profile updated.')).catch(() => setMessage('Could not save changes.')).finally(() => setBusy(false)); }} /><Button label="Done" variant="secondary" onPress={() => navigation.goBack()} /></Card></ScrollView></Screen>;
}

export function ConnectionsScreen({ route, navigation }: ChildScreenProps<'Connections'>) {
  const { session } = useAuth(); const mode = route.params?.mode ?? 'followers'; const [tab, setTab] = useState(mode); const [data, setData] = useState<{ followers: unknown[]; following: unknown[] }>({ followers: [], following: [] }); const [error, setError] = useState<unknown>(null);
  useEffect(() => { if (session) fetchConnections(session.token).then((r) => setData({ followers: r.followers, following: r.following })).catch(setError); }, [session?.token]);
  if (error) return <Screen><GateNotice error={error} /><ErrorState message="Connections are unavailable." /></Screen>;
  const people = (tab === 'followers' ? data.followers : data.following) as Person[];
  return <Screen><Text style={styles.heading}>Connections</Text><View style={styles.tabs}>{(['followers', 'following'] as const).map((t) => <Pressable key={t} onPress={() => setTab(t)}><Text style={[styles.tab, tab === t && styles.active]}>{t.toUpperCase()}</Text></Pressable>)}</View><FlatList data={people} keyExtractor={(p, i) => `${personId(p)}-${i}`} ListEmptyComponent={<EmptyState title="No connections yet" body="Approved friends will appear here." />} renderItem={({ item }) => <Pressable style={styles.person} onPress={() => personId(item) && navigation.navigate('OtherProfile', { targetId: personId(item) })}><Avatar uri={item.avatar_url} name={item.full_name ?? item.username ?? 'Friend'} size={44} /><View><Text style={styles.body}>{item.full_name ?? item.username ?? 'Friend'}</Text><Text style={styles.sub}>Approved friend</Text></View></Pressable>} /></Screen>;
}

export function NewMessageScreen({ navigation }: ChildScreenProps<'NewMessage'>) {
  const { session } = useAuth(); const [people, setPeople] = useState<Person[]>([]); const [q, setQ] = useState(''); const [error, setError] = useState<unknown>(null);
  useEffect(() => { if (session) fetchConnections(session.token).then((r) => setPeople(r.following.concat(r.followers) as Person[])).catch(setError); }, [session?.token]);
  const filtered = people.filter((p, i, all) => personId(p) && all.findIndex((x) => personId(x) === personId(p)) === i && `${p.full_name ?? ''} ${p.username ?? ''}`.toLowerCase().includes(q.toLowerCase()));
  return <Screen><Text style={styles.heading}>New message</Text><Field label="Search approved friends" value={q} onChangeText={setQ} autoCapitalize="none" />{error ? <GateNotice error={error} /> : null}<FlatList data={filtered} keyExtractor={(p, i) => `${personId(p)}-${i}`} ListEmptyComponent={<EmptyState title="No approved friends" body="Messaging opens after both families approve a connection." />} renderItem={({ item }) => <Pressable style={styles.person} onPress={() => navigation.navigate('Chat', { peerId: personId(item) })}><Avatar uri={item.avatar_url} name={item.full_name ?? item.username ?? 'Friend'} size={44} /><Text style={styles.body}>{item.full_name ?? item.username ?? 'Friend'}</Text></Pressable>} /></Screen>;
}

export function ChatDetailsScreen({ route, navigation }: ChildScreenProps<'ChatDetails'>) {
  const { session } = useAuth(); const peerId = route.params.peerId; const [muted, setMuted] = useState(false); const [message, setMessage] = useState('');
  const act = (fn: (token: string) => Promise<unknown>, done: string, nextMuted?: boolean) => { if (!session) return; fn(session.token).then(() => { setMessage(done); if (nextMuted !== undefined) setMuted(nextMuted); }).catch(() => setMessage('That safety action could not be completed.')); };
  return <Screen><ScrollView><Text style={styles.heading}>Chat details</Text><Card><Text style={styles.sub}>Your conversation is private and protected by LittleNet safety checks.</Text><Button label="Open chat" onPress={() => navigation.navigate('Chat', { peerId })} /></Card><Card><Text style={styles.section}>Safety controls</Text><Button label={muted ? 'Unmute friend' : 'Mute notifications'} variant="secondary" onPress={() => act((t) => muteUser(t, peerId, muted ? 'UNMUTE' : 'MUTE'), muted ? 'Notifications on.' : 'Notifications muted.', !muted)} /><Button label="Block friend" variant="secondary" onPress={() => act((t) => blockUser(t, peerId, 'BLOCK'), 'Friend blocked.')} /><Button label="Report conversation" variant="secondary" onPress={() => act((t) => submitReport(t, 'USER', peerId, 'Unsafe behavior'), 'Report sent for safety review.')} />{message ? <Notice tone="info" message={message} /> : null}</Card></ScrollView></Screen>;
}

const styles = StyleSheet.create({ heading: { fontSize: 26, fontWeight: '800', color: colors.ink, padding: 16, paddingBottom: 4 }, sub: { color: colors.muted, paddingHorizontal: 16, lineHeight: 20 }, tabs: { flexDirection: 'row', justifyContent: 'space-around', borderBottomWidth: 1, borderColor: colors.line, paddingVertical: 14, marginTop: 12 }, tab: { fontSize: 12, fontWeight: '800', color: colors.muted }, active: { color: colors.ink }, body: { color: colors.ink, fontWeight: '700' }, person: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: 14, borderBottomWidth: 1, borderColor: colors.line }, section: { fontSize: 16, fontWeight: '800', color: colors.ink } });