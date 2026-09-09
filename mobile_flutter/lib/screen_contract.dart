enum LittleNetExperience { authentication, kids, parent, admin, settings }

class LittleNetScreenSpec {
  const LittleNetScreenSpec(this.id, this.name, this.experience, {this.inlineWith});

  final int id;
  final String name;
  final LittleNetExperience experience;
  final int? inlineWith;
}

const littleNetScreenContract = <LittleNetScreenSpec>[
  LittleNetScreenSpec(1, 'Splash Screen', LittleNetExperience.authentication),
  LittleNetScreenSpec(2, 'Choose User', LittleNetExperience.authentication),
  LittleNetScreenSpec(3, 'Parent Login & Signup', LittleNetExperience.authentication),
  LittleNetScreenSpec(4, 'Child Login', LittleNetExperience.authentication),
  LittleNetScreenSpec(5, 'Create Child Account', LittleNetExperience.authentication),
  LittleNetScreenSpec(6, 'Parent–Child Linking & Consent', LittleNetExperience.authentication),
  LittleNetScreenSpec(7, 'Face Enrollment / Liveness', LittleNetExperience.authentication),
  LittleNetScreenSpec(8, 'Kids Home Feed', LittleNetExperience.kids),
  LittleNetScreenSpec(9, 'Feed Tabs', LittleNetExperience.kids, inlineWith: 8),
  LittleNetScreenSpec(10, 'Post Detail', LittleNetExperience.kids),
  LittleNetScreenSpec(11, 'Comments & Replies', LittleNetExperience.kids),
  LittleNetScreenSpec(12, 'Create Post', LittleNetExperience.kids),
  LittleNetScreenSpec(13, 'Post Preview & AI Safety Check', LittleNetExperience.kids),
  LittleNetScreenSpec(14, 'Share / Save Sheet', LittleNetExperience.kids),
  LittleNetScreenSpec(15, 'Report / Hide Sheet', LittleNetExperience.kids),
  LittleNetScreenSpec(16, 'Story Viewer', LittleNetExperience.kids),
  LittleNetScreenSpec(17, 'Create Story', LittleNetExperience.kids),
  LittleNetScreenSpec(18, 'Story Editor', LittleNetExperience.kids),
  LittleNetScreenSpec(19, 'Story Safety Check & Publish', LittleNetExperience.kids),
  LittleNetScreenSpec(20, 'Reels Feed', LittleNetExperience.kids),
  LittleNetScreenSpec(21, 'Reel Comments', LittleNetExperience.kids, inlineWith: 11),
  LittleNetScreenSpec(22, 'Create Reel', LittleNetExperience.kids),
  LittleNetScreenSpec(23, 'Reel Editor', LittleNetExperience.kids),
  LittleNetScreenSpec(24, 'Reel Preview & Moderation', LittleNetExperience.kids),
  LittleNetScreenSpec(25, 'Reel Detail / Share', LittleNetExperience.kids),
  LittleNetScreenSpec(26, 'Explore', LittleNetExperience.kids),
  LittleNetScreenSpec(27, 'Search', LittleNetExperience.kids),
  LittleNetScreenSpec(28, 'Search Results', LittleNetExperience.kids),
  LittleNetScreenSpec(29, 'Blocked / Unsafe Search', LittleNetExperience.kids),
  LittleNetScreenSpec(30, 'DM Inbox', LittleNetExperience.kids),
  LittleNetScreenSpec(31, 'One-to-One Chat', LittleNetExperience.kids),
  LittleNetScreenSpec(32, 'New Message', LittleNetExperience.kids),
  LittleNetScreenSpec(33, 'Group Chat', LittleNetExperience.kids),
  LittleNetScreenSpec(34, 'Chat Info / Block / Report', LittleNetExperience.kids),
  LittleNetScreenSpec(35, 'Unsafe Message / Image Warning', LittleNetExperience.kids),
  LittleNetScreenSpec(36, 'My Profile', LittleNetExperience.kids),
  LittleNetScreenSpec(37, 'Other User Profile', LittleNetExperience.kids),
  LittleNetScreenSpec(38, 'Edit Profile', LittleNetExperience.kids),
  LittleNetScreenSpec(39, 'Followers / Following / Friends', LittleNetExperience.kids),
  LittleNetScreenSpec(40, 'Friend / Follow Requests', LittleNetExperience.kids),
  LittleNetScreenSpec(41, 'Saved Content', LittleNetExperience.kids),
  LittleNetScreenSpec(42, 'Notifications Centre', LittleNetExperience.kids),
  LittleNetScreenSpec(43, 'Learning Hub', LittleNetExperience.kids),
  LittleNetScreenSpec(44, 'Educational Feed / Reels', LittleNetExperience.kids),
  LittleNetScreenSpec(45, 'Quiz List', LittleNetExperience.kids),
  LittleNetScreenSpec(46, 'Quiz Play & Result', LittleNetExperience.kids),
  LittleNetScreenSpec(47, 'Learning Challenges', LittleNetExperience.kids),
  LittleNetScreenSpec(48, 'Safety Centre', LittleNetExperience.kids),
  LittleNetScreenSpec(49, 'Report User / Content', LittleNetExperience.kids),
  LittleNetScreenSpec(50, 'Moderation Result', LittleNetExperience.kids),
  LittleNetScreenSpec(51, 'Report History / Status', LittleNetExperience.kids),
  LittleNetScreenSpec(52, 'Parent Dashboard', LittleNetExperience.parent),
  LittleNetScreenSpec(53, 'Child Activity', LittleNetExperience.parent),
  LittleNetScreenSpec(54, 'Parent Alerts', LittleNetExperience.parent),
  LittleNetScreenSpec(55, 'Parent Review', LittleNetExperience.parent),
  LittleNetScreenSpec(56, 'Screen-Time Dashboard & Controls', LittleNetExperience.parent),
  LittleNetScreenSpec(57, 'Smart Controls', LittleNetExperience.parent),
  LittleNetScreenSpec(58, 'Admin Dashboard', LittleNetExperience.admin),
  LittleNetScreenSpec(59, 'Moderation Queue', LittleNetExperience.admin),
  LittleNetScreenSpec(60, 'Moderation Review', LittleNetExperience.admin),
  LittleNetScreenSpec(61, 'Settings & Language', LittleNetExperience.settings),
];

LittleNetScreenSpec littleNetScreen(int id) =>
    littleNetScreenContract.firstWhere((screen) => screen.id == id);
