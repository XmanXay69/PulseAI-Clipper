import Foundation

/// The links the study library ships with: one line per video, tab-separated
/// (genre, video id, views, length in seconds, channel, title).
///
/// Built on 2026-11-14 by scripts in the session that added the library, from two sources: the 42 videos
/// already watched for the 1.9.0 styles (docs/editing-study-notes), and what YouTube's search returned for
/// `StudyFinder.queries`, in its own order and most-watched first, kept when `StudyFinder.accepts` took them
/// and listed most watched first. The view counts are as YouTube showed them that day. It is the most
/// watched of what those searches found, not a ranking of everything on YouTube.
enum StudySeeds {
    static let gatheredOn = "2026-11-14"
    static let videos: [LibraryVideo] = parse(table)

    static func parse(_ table: String) -> [LibraryVideo] {
        var seen = Set<String>()
        return table.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 6, let genre = VideoGenre(rawValue: fields[0]), !fields[1].isEmpty, seen.insert(fields[1]).inserted else { return nil }
            return LibraryVideo(videoID: fields[1], title: fields[5...].joined(separator: " "), channel: fields[4], genre: genre,
                                views: Int(fields[2]), duration: Double(fields[3]), origin: .shipped)
        }
    }

    static let table = #"""
streamHighlights	lfKcnDZ7ZOA	354503	2000	Joshyy	How to Edit a Fortnite Highlights Video in Davinci Resolve (Intro Text, Transitions, Glow, Etc.)
streamHighlights	5RuoLQWvDu8	224425	600	Senpai	How To Edit Your Twitch Streams Into YouTube Videos
streamHighlights	57azbqwdcqM	175660	418	Patrick Stirling	The Easiest Ways to Edit Hours of Gameplay Footage
streamHighlights	X95RyfDPQmA	132732	1464	Joshyy	How to Edit a Fortnite Highlights Video in Davinci Resolve (Wavy Text, Shakes, Blurs, Etc.)
streamHighlights	HbJkFDvVlLs	109593	1247	Gael LEVEL	6 ways to Turn Twitch Clips into YouTube Shorts, Reels & TikToks
streamHighlights	3WX25xdYnMo	106332	1235	Stream Scheme	How To Use Twitch Clips To Get 2.5 Million Views On TikTok
streamHighlights	C_7lL0TfYVM	93323	328	Nikita Cheldiev	How To Edit Twitch Clips For TikTok - Creator Rewards Program (2024)
streamHighlights	x5frer5MoKk	87523	597	Cpaws Music	How To EDIT Your Twitch Streams 2026 (For Beginners)
streamHighlights	sY2AxvO3cUM	40453	516	Cpaws Music	How To Edit Your Twitch Streams Into TikToks & YouTube Shorts
streamHighlights	vFEYKJPr0uM	37188	403	Gagal Sarjana	How to Properly Edit Long-Form VODs for Professional Facebook Creators
streamHighlights	EVCCGP3qEXY	34967	931	Gael LEVEL	Twitch Clips Highlights Tutorial - Video Editing for beginners (Basics)
streamHighlights	6kQSCZZQO4c	33093	1170	Moorph	How to Edit Videos on YouTube and Twitch Like a Pro
streamHighlights	fs9mXLcOdc8	32906	678	Joshyy	How to Edit the *BEST* Fortnite Highlights in PREMIERE PRO (2021)
streamHighlights	tuyYOtW477o	28124	785	Cpaws Music	How To Edit Your Kick Streams Into TikToks & YouTube Shorts
streamHighlights	Bq6R_uL44ao	17360	734	Zocki's Nerdtechzone	How to Edit Highlights from a Stream (OBS, Twitch Marker Feature)
streamHighlights	qTr_pveGlOA	15858	469	RuthlessNightsister	How To Edit Twitch Clips for TikTok and Instagram (For Free!) - CupCut App Tutorial
streamHighlights	jMcSzKhH390	10911	253	EposVox	How to edit stream highlights WITHOUT encoding! Fastest video editing w/ XSplit Express Video Editor
streamHighlights	PM7OijUCS7U	10608	202	HunterTheHill	How To Edit Stream VOD into YouTube Shorts (Clips) in Davinci Resolve
gamingVideo	sLgHqZSe2o0	6071408	872	Learn By Leo	How to edit SO good your viewers get addicted to your videos
gamingVideo	ae_tzdPGyis	4375165	679	RADAL	how to edit gaming videos
gamingVideo	hhhSRaTP_mI	2324273	1397	CreaView	How to Edit Gaming Videos Like Pro on Mobile in 2026 (Basic to Advanced Full Tutorial)
gamingVideo	H1LdSmObFhg	2010793	398	finzar	How to Edit Gaming Subtitles (Premiere Pro)
gamingVideo	lYj7Mouw-dc	1553486	835	Finzar	How to Edit a Gaming Video (For Beginners)
gamingVideo	hDS4tr0KpK8	1476532	594	RADAL	how to edit gaming videos like a god
gamingVideo	GqNuZv-GxJk	1367410	395	Vijay Dhanbadi	How to Edit Comedy Videos | How to Add Memes and Sound Effects to Comedy Videos
gamingVideo	2mjhvGD5mU0	1187196	396	BM Tech	How To Edit Gameplay Video On Kinemaster With FaceCam | kinemaster Gaming Video Editing Tutorial
gamingVideo	jYqH0P4BwvI	1066511	938	MidnightMan	How To Edit Gaming Videos Like a Pro Using CapCut Desktop
gamingVideo	IlKZS02_yY8	1032344	1541	Tube Sensei	Edit Gaming Videos Like A Pro On Mobile | Beginner To Advance Editing
gamingVideo	8Mw2rK4Ch1o	925558	780	Chieyo	ARABIAN NIGHTS ROBLOX EDIT TUTORIAL ON CAPCUT!
gamingVideo	QtOumf09MEQ	872910	616	Finzar	Stop Editing For SO LONG!
gamingVideo	6h5NsjPub4o	780766	421	MortarMarv	How To Edit Funny Gaming Videos Like A Pro (Premiere Pro Tutorial)
gamingVideo	Ormb3Z0QJVs	753369	688	Finzar	How To Edit Memes in Your Gaming Videos (3 EASY WAYS)
gamingVideo	D5H6wdrB7e0	736639	490	Finzar	How to Edit a Funny Gaming Video
gamingVideo	J9sdBXe9LQk	728584	635	JamFam	HOW TO EDIT GAMING VIDEOS [PREMIERE PRO TUTORIAL]
gamingVideo	9Pn7uGmIU9E	718209	520	MortarMarv	How To Edit Gaming Videos For Beginners
gamingVideo	dfOffqhCiwo	695028	564	Finzar	How To Edit Sound Effects (Premiere Pro)
gamingVideo	RmMpeXWP3I8	655418	680	ItsProger	How To Edit VIRAL Minecraft Videos
gamingVideo	lODhwmdCudM	616666	776	Finzar	How To Edit: Ultimate Beginner's Guide
gamingVideo	mCGOMcfa0l0	508381	581	Abhay PS Rajawat	How I would Edit a Viral Gaming Video in 2026
gamingVideo	8TWko8g0AyM	486787	702	𝐜𝐚𝐥𝐥𝐢𝐞 🤍	NOT MY PROBLEM ROBLOX EDIT TUTORIAL!! // NotCrazyCallie // capcut & videostar pro
gamingVideo	_laioiIuvtw	445597	604	Finzar	How I'd Edit a Viral Gaming Video in 2026
gamingVideo	55EITbIorKM	444408	339	Gallix	2026🔥 | How To Add Memes In Gaming Video In Capcut | Pro Editing Tips And Tricks 2024
gamingVideo	Cqkgst1mRo0	441464	718	Finzar	I Took a New Editor from Beginner to PRO in 8 Hours
gamingVideo	_EElbjcCgIw	409708	1286	Ruturaj Studio	How To Edit Gaming Videos Like A Pro In CapCut Mobile
gamingVideo	XYVqyQWUeoU	403703	1388	Rocklan	How to make a Valorant Montage in Capcut! (FREE VIDEO EDITOR!)
gamingVideo	G9dj3E6oQkU	398828	217	lil yay	Valorant TikTok Edit GUIDE in CapCut
gamingVideo	FQVF6wRYQSQ	389578	281	Zapnow playz	Edit Engaging Videos🔥 || How To Edit Minecraft Videos In Mobile ✅
gamingVideo	i72rQaXJ91k	388953	577	Finzar	I made 100+ gaming videos. This is what I learned...
gamingVideo	KRB-s7Q2LMo	345530	333	finzar	How To Edit FASTER In Premiere Pro! (5 Tips)
gamingVideo	GnZFNE4pz5I	317967	433	finzar	How To Edit 21st Century Humour Memes (Premiere Pro)
gamingVideo	Xsdq23-cfT4	287163	541	Finzar	How To Edit Gaming Videos With Music (Premiere Pro)
gamingVideo	zZZ4kkmFP0c	258666	627	JamFam	The ULTIMATE Editing Guide for Gaming Videos [Premiere Pro Tutorial]
gamingVideo	Yem5uwLzF70	227262	239	Collin Michael	How To Edit Mobile Gaming Videos Like a Pro!
gamingVideo	JJtWqHJlUfI	221929	636	MidnightMan	0 VIEWS on Your Gaming Videos? 10 SIMPLE Techniques To Edit Like a Pro!
gamingVideo	7a-NtmHCqto	219920	488	finzar	How To Edit Rotoscoped Memes (After Effects/Premiere Pro)
gamingVideo	dOzmWkuJuq4	211157	313	Exrtive	How to INSTANTLY EDIT FASTER in Fortnite! (Console & PC)
gamingVideo	QlxRnD6vW2A	201098	482	HifzanBreaks	Gaming Video Editing Just Like A PRO 🔥! (to win in 2024 on Youtube)
gamingVideo	MTlklhG4kmI	193552	536	YouTopia	HOW TO EDIT GAMEPLAY VIDEOS THE WAY THAT MAKES YOU ROCK!
gamingVideo	2QPpIl0_ZbE	189767	568	finzar	How I’d Make Money Editing Videos in 2026
gamingVideo	VERfm7Yldgk	186809	1922	Rocklan	How to Edit a Gaming Montage in 2024 (For Beginners) Adobe Premiere Pro Tutorial
gamingVideo	xmfSCKV7qUE	186695	1332	Finzar	How To Edit YouTube Videos in 2026 (Ultimate Guide)
gamingVideo	RYtHsQawr9c	166159	883	Kavangun	How to NOT edit Gaming Videos? | Editing Review pt.1
gamingVideo	CqLyX8_D0fs	158177	633	MidnightMan	How To Edit Gaming Videos Using CapCut! (EASY)
gamingVideo	fOfz9-BQUII	154011	813	finzar	How To Edit Like RADAL (Premiere Pro)
gamingVideo	VaSex5JEGBo	153644	786	Kris Seredis	How To Make The *CLEANEST* Fortnite Montage (How To Edit Like Clix)
gamingVideo	RLLA8lIkHTk	149198	276	finzar	How To Kickstart Your Editing Career
gamingVideo	LGOyTAV22vA	143700	512	Reio Riisna Branding	50 MUST-KNOW EDITING TIPS FOR GAMING VIDEOS/CLIPS in 8 minutes
gamingVideo	bPjQXNnofDI	142183	652	CreaView	Top 7 Gaming Video Editing Tricks you MUST KNOW in 2026 (Edit Like a PRO)
gamingVideo	np1g8LVhV6I	137706	1215	sieon	How I make my MOST VIRAL VALORANT EDITS [Tutorial] *Beginner Friendly*
gamingVideo	32LZg7c1yFc	129848	2582	Casey Faris	Editing Gaming Videos in DaVinci Resolve - The Ultimate Beginner's Guide
gamingVideo	GSa4K33RgEg	125747	379	NotMoonfly	Davinci Resolve 15/16/17 Meme Editing Tutorial
gamingVideo	zW8jiE771Ek	113816	410	finzar	How to Make and Edit a Comedy Sketch For YouTube
gamingVideo	0B1Nk0zdUHo	98255	406	Great Jas	How to Edit Minecraft Videos Like a Pro 🔥 || How To Edit Minecraft Videos In Capcut
gamingVideo	p0hpwgq08JY	94778	559	BunnyFoyOfficial 1M	How To Edit Minecraft Videos On Android 😍 | How To Edit Minecraft Videos In KineMaster |
gamingVideo	008RHJWNmKw	90006	633	Sam Woodhall	Editing Secrets for Epic Gaming Videos
gamingVideo	EvfrbUqb3fc	83901	610	KillerMiller	How to Edit Valorant Clips for Tiktok!
gamingVideo	asSBYus1daQ	80333	1703	Ibadra	How To Edit Horror Gaming Videos (Like CoryXKenshin & 8-BitRyan) | DaVinci Resolve Tutorial
gamingVideo	YBfmF34nYCo	78011	333	TommorCut	Edit Gaming Videos Like a Pro on Mobile | Beginner to Advanced Editing
gamingVideo	tE-HAGli_dU	73845	405	Cocajola	⌨️How To Edit Roblox VIDEOS! FREE! (EASY, BEGINNER!)
gamingVideo	ayOj37c1teY	71232	808	SuN RsK	How To Edit Gaming Videos (Full Process) 🔥
gamingVideo	RutTgrCATwk	69740	516	Finzar	The Secret To Editing Professional Videos in 2026
gamingVideo	gdjCDL5uCJw	65213	531	Sam Woodhall	Simple Editing Secrets For Better Gaming Videos
gamingVideo	ZOkb9O4mMTE	64148	214	Korelta	How to EDIT ROBLOX YOUTUBE VIDEOS…
gamingVideo	5NMqHGkgoUc	62789	1340	HifzanBreaks	GAMING VIDEO EDITING JUST LIKE A PRO 🔥!
gamingVideo	YQnmtwQrZDI	62401	415	Cocajola	⌨️How To Edit Roblox VIDEOS! FREE! (2023!)
gamingVideo	ayeBVkq7uSk	59565	2123	Ibadra	How To Edit The ULTIMATE Gaming Video | DaVinci Resolve (ANY software) Tutorial
gamingVideo	RcsVRQcCybM	55668	194	VoidPurple	How I Actually Edit My Roblox Videos | CapCut Tutorial
gamingVideo	02yN8llJ9UU	51175	1095	XiTrOnEexe	How to edit gaming.exe meme videos | Davinci Resolve 17
gamingVideo	kzoLKBfEdbo	44025	1263	Collin Michael	How To Edit Gaming Videos In CapCut PC (2025)
gamingVideo	NG96SqIn-Ms	40357	365	Premium Rise	5 Editing Tricks That Make Gaming Videos Better (Mobile)
gamingVideo	n_ypUqlMdV8	39445	494	Casian Dumitrescu	How To Edit VIRAL Roblox Videos
gamingVideo	iHk9KL5GRD0	39043	459	Pqtrick	How To Edit Minecraft Videos
gamingVideo	XKbEhfpW0Yw	39016	299	BingoRBX	How To EDIT SMOOTH GAMING Videos In DaVinci Resolve...(FREE)
gamingVideo	OkNKxw-IMGc	38392	504	Flinch - Grow on Youtube	How to Edit Gaming Videos Like the Top 1%
gamingVideo	LMjBO6cLdSs	38126	647	Viddyoze	How to Edit Gaming Videos for YouTube (DaVinci Resolve 2025)
gamingVideo	_3zM-iswdSQ	37884	817	NitroBeam	ROBLOX EDITING TUTORIAL
gamingVideo	pG0euuJUPT0	37430	1136	MC Creator Tech Help	DaVinci Resolve - Basics of Minecraft editing!
gamingVideo	oOho_Egu0Jc	35153	689	LAS Curry	How to Edit Gaming Videos in CapCut (Step by Step)
gamingVideo	abExstEjhjs	32812	761	Ruturaj Studio	How to Edit Gaming Videos Like a PRO Step by Step Guide
gamingVideo	L_wbhhBR0kk	31475	471	Cosmic Creators	How To Edit Minecraft Videos On Capcut
gamingVideo	Ccg7py0mBkw	29095	375	Greens Animator	How To Edit PROFESSIONAL Minecraft videos | ULTIMATE GUIDE
gamingVideo	LOJXhrem68g	25902	556	Nathan	How to EDIT GAMING VIDEOS in DaVinci Resolve 16 \\ Quick tips for BEGINNERS
gamingVideo	eTg-Y5-nYqE	24269	456	DNStream	How To Edit Minecraft Videos?! | PART 1
gamingVideo	FxM_GcPPeRs	23131	251	AceRoblox	How TO edit ROBLOX videos!
gamingVideo	9c4AeaqWGGg	22947	1432	Trevor Jones	How To Edit Gaming Videos in CapCut for Beginners
gamingVideo	yOe0G7-0FFw	22917	939	ItsKingTimツ	How To Make A Fortnite Montage on Capcut For Beginners! 2026 (Tutorial & EASY!)
gamingVideo	wM4nXX6jql8	21246	660	Rezently	How To EDIT A Fe4rLess Video! - Edit Fortnite Videos Like Fearless (Davinci Resolve 18)
gamingVideo	sgeeEcwskaU	21108	394	Wondershare Filmora Video Editor	How to Get Better at Editing Gaming Videos | Filmora Creator Tips
gamingVideo	7nMZBHSqev8	19056	458	Cocajola	How To Edit Roblox Videos On MOBILE! FREE! (EASY!)
gamingVideo	GrdvgRkjkh4	19038	306	Wondershare DemoCreator	How to Edit Gaming Videos for YouTube | 5 Steps to Edit Gameplay Videos
gamingVideo	wkUi5J9mrnA	17863	316	Premium Rise	How to Edit Gaming Videos on Mobile Like a PRO (Beginner to Advanced)
gamingVideo	WZGwhZZb8d8	17231	1443	Michael Feyrer Jr.	How To Edit Gaming Videos Like a Pro Using CapCut Desktop PC & Mac
gamingVideo	Szgri3rvT4g	15368	559	Jewel The Jet	Giants Editor Tutorial | How To Fix Error Game Installation Path Error FS19 FS22 | Tutorial
gamingVideo	sNTajsNrQWk	14260	1056	LAS Curry	How to Edit Gaming Videos in DaVinci Resolve (Step-by-Step)
gamingVideo	Eal6WXe9uog	13948	3421	Niko	How to Edit VIRAL Fortnite Videos in 2025
gamingVideo	0HpK0n7AmaE	13820	444	AceRoblox and AceRoblox 2	How to edit Roblox videos on CapCut part 2! (Part 2)
gamingVideo	eEVxr6lzQSc		596	Finzar	How To Edit Super Smooth Transitions in Premiere Pro!
gamingVideo	L4da128D6Xc		187	Storezar	How to Edit The BEST Sound Effects For Beginners
challenge	t5Z-Q1bg1tU	3029915	674	Kallaway	How To Become A Master Storyteller
challenge	iWQQgZh9EyE	2317808	817	Film Riot	Visual Storytelling 101
challenge	F0d89mlFa1U	2007136	1838	DecodingYT	8 Editing Techniques to Make VIRAL YouTube Videos
challenge	QR8LxximqWI	1853753	351	HillierSmith	5 MORE Editing Mistakes YouTubers Do That I Hate...
challenge	D5RkABUQfkM	1383063	545	NSB Pictures	The Art of Storytelling: a complete guide - NSB Pictures
challenge	grzBWXN0oxI	1155930	1613	Exal.Visuals	How to Make VIRAL EDITS on Capcut | Full Tutorial ✨
challenge	5He0fCy5f0w	1103850	626	Little Ingredient	How I film & edit YouTube video with my iPhone
challenge	hY4pybwOUq0	1086880	411	vidIQ	4 Editing Secrets Small Channels Learn Too Late
challenge	IjMVme1aDWg	930231	685	byl	How I Edit Documentary Video LIKE Johnny Harris in Capcut (Part 1)
challenge	MJHpo7pOaLg	869895	688	Zeven 7	How to Make Viral Minimal Reel Edits in CapCut
challenge	ciAywjey0cY	800261	1327	Isaac	How I Actually Edit Viral Videos
challenge	J0ydlAqg6_8	758777	564	Tim Runia	The ONLY 7 Cuts You Need To Tell Any Story
challenge	Zm7J3KqqXPk	586303	503	Herman Huang	How to Edit ANY Video Like You've Done it 1,000 Times
challenge	R8yEvQ0lx-s	577913	338	Film Booth	How To Edit YouTube Videos 10x Faster! - Productivity Hacks
challenge	nZrPVUzYHKE	543483	468	Motion Array Tutorials	How To Edit A Documentary Like Johnny Harris
challenge	z2FoMcL6KuQ	509586	740	Trevor Jones	How To Edit Like Mr Beast In CapCut
challenge	RBvIv-LfVBE	472324	553	Nate Curtiss	How to Edit Viral Videos
challenge	FxUOOqMoHeY	398253	1183	Ruturaj Studio	How to Edit Videos Like MrBeast in CapCut #capcut #mrbeast
challenge	Yb0GVSqY0H4	392883	496	CbullyVFX	I Made a SECRET Editing Account for 7 Days and Went VIRAL!?
challenge	IPW-MF8Kp0I	375835	676	LOGAN SMITH	How to get retention SO HIGH your shorts always go viral
challenge	7CP9MOTBgyE	356331	1208	Skeppy	I Secretly Became This Minecraft YouTubers Editor...
challenge	MGj23Vfliso	355414	1130	Amplify Views	How to Master the Art of YouTube Storytelling
challenge	dhpazqW_OaU	353507	756	Tim Runia	The ONLY 5 Editing Secrets You Need to Tell Any Story
challenge	Zf2jQm8xA_I	353083	843	Technical Sky	Edit your YouTube Videos Professionally - For Beginners
challenge	AV4UnrHznR8	304636	1100	Think Media	How to Edit a YouTube Video in 2026 (Start to Finish)
challenge	rJKzlE7aMBw	297962	484	finzar	How To Edit Like Mr Beast (YouTube Cheat Sheet)
challenge	g9xoKm5DEeU	250693	1257	Joseph | Video Editing	How to Edit VIRAL Talking Head Videos Using ONLY Claude! (New Minimal Style)
challenge	BEOGncyhwNo	224010	500	TaZerrr	How to Edit on Capcut so You ALWAYS Go Viral
challenge	rp6cTMARWkA	218322	2869	Content Creators	Edit PRO Youtube Videos in DaVinci Resolve | In Depth Tutorial
challenge	7F0Qb4RCr6s	198754	533	Abhay PS Rajawat	the only 5 Storytelling Tips you Need as a Video Editor
challenge	dijLCofg8WE	197669	269	Marketing Demons	How To Actually Edit Viral Videos (Under 5 Minutes)
challenge	PIjeg7mAF4g	182499	1608	Aprilynne Alter	how to EDIT a killer youtube video (to blow up your channel)
challenge	42ukI3kJpXY	172495	932	Matt Loui	How To Edit A Documentary Like Johnny Harris in CapCut
challenge	mgEC7Bepq18	166671	2231	Vane Motion	How to EDIT DOCUMENTARY Style videos | Full tutorial from scratch
challenge	YKyczxU3n3M	131461	550	Jenn Jager	How to Edit YouTube Videos in 2026 | Complete Beginner Guide!
challenge	ODRJkEGTI_U	129342	448	Nate Curtiss	7 YouTube Editing Tips to Instantly Boost Retention
challenge	_gER3oFvET8	124468	1908	AEffecto	How To Make Documentary Video Editing Style | After Effects Tutorial
challenge	6CcdXcuO9D0	122822	703	Mark Johansson	How to Edit a Documentary Film
challenge	_MbHN-9d30Y	113866	1209	Mark Bone	Foundations of Documentary Editing - How to Edit Scenes Like A Pro
challenge	EOzOO77ltVk	102051	1424	Creative Graphicz	How to EDIT Documentary Style Videos | Filmora Tutorial
challenge	QQlA5khhVhc	95182	270	Mooxion	How to Edit Like MrBeast in CapCut (5 KEYS)
challenge	wB6AHR_w5iQ	92162	853	Maya Love	How To Edit Like A Pro And Keep Viewers Hooked On Your Videos
challenge	feVFs8OMfmg	91977	833	Bart_VFX	How to Make Documentary Editing Style | After Effects Tutorial
challenge	6RkyyjQKYIA	88538	975	BogXD	How to edit for retention (feedback to a video editor)
challenge	rwsLUKw1n54	64671	1235	Will Carmack	How To Edit Like Mr Beast In After Effects | 5 EASY EFFECTS
challenge	DnQUBMBAQDM	57080	948	Queen keren	CapCut Editing Tips: 5 Essential Features To Hook Your Viewers!
challenge	yQK4bjoxO1w	53690	683	Tim Runia	5 Easy Editing Tricks for More Powerful Storytelling
challenge	f2BJksCVK-4	53298	907	BogXD	How to edit for retention (feedback to a video editor) pt. 2
challenge	V1gRnzWw3t4	50306	1356	GlowingAi	How to Edit Like MrBeast... on Mobile
challenge	9Yl1a79Z3k4	47241	345	Zane Hoyer	Edit Like MrBeast in DaVinci Resolve & Blender – 3D Effects Tutorial
challenge	Au1IB_sHlWE	46583	860	Mark Johansson	How to Edit a 10-Minute Documentary
challenge	CDAemwBoHtc	44629	984	luvkilomedia	Documentary Style Editing Like Netflix (After Effects Tutorial)
challenge	ooWMvH3341k	36584	1082	Learn By Leo	Every viral RETENTION TACTIC explained (with examples)
challenge	Pi0yhInZRsg	35975	704	Abhay PS Rajawat	Storytelling Techniques I use to get viewers addicted to my videos
challenge	f3G8Ub3rc6A	34751	592	Deny King	How To Edit Documentary Videos in CapCut | 3 Editing Effects
challenge	lnF3TUIWkO4	34688	1326	Joseph | Video Editing	How to Edit VIRAL Talking Head Videos Using Fable 5.2! (New Premium Style)
challenge	UKDuxcYDBho	34584	434	Just Create Ryan	8 Easy Editing Tricks I Use to Consistently Hit 60% Retention
challenge	rkRclFUU-aw	30421	385	Virginia Kerr	4 Editing tricks that BOOST YouTube Retention
challenge	8liW9ZKyxLM	26114	190	Hot Sauce Video	Storytelling in Video with These 5 Editing Tips
challenge	0gwThlsGGFE	21330	548	Bog	How to edit SO good your viewers get addicted to your videos
challenge	c6X-Ywy3yVU	20903	675	Nate Black	I Found 3 Retention Techniques that Make Videos BLOW UP
challenge	NXVbtp3YrBM	18507	1697	BeTheCut	High Retention Editing in 2026 | CAPCUT TUTORIAL
challenge	2B-jbgAQJ_I	16629	219	Noé	How to Edit the Best Storytelling Video
challenge	RRHe_tzJcQg	15840	1008	Karl Watson: Travel Documentaries	How To Make A Travel Video: Pt3 - How to edit your story
challenge	ZYYeHnuzcsY	14235	1036	Will Carmack	How To Edit Like Mr Beast In After Effects | 5 MORE EASY EFFECTS
vlog	Q980C74SdYQ	6247613	849	Casey Neistat	How to vlog like Casey Neistat
vlog	zjYC40zvSws	2186491	1007	Riya Bhattacharyya09	How to edit Vlogs easily || Video Editing full tutorial || InShot Tutorial
vlog	DrRPlCke1yg	1378034	889	GROW with ME	How to make mini vlogs? How to make mini vlogs? How to edit mini vlogs? Mini vlog editing
vlog	Ud-9hevttnk	1188849	620	Techno Avneesh	How to edit a Pro Mini vlog? | How to do voice over on a Mini Vlog? | How to make a Pro Mini Vlog
vlog	DKPrVAqRnsk	1143617	1307	NoisyButters	Day In the Life of a Gaming YouTuber + How I Edit / Record Videos! | NoisyButters
vlog	RyQfoWvAHyE	1075384	1374	P J Cinematic Ideas	HOW TO EDIT CINEMATIC SHOTS FOR VLOGS | MOBILE VIDEO EDITING USING VN APP
vlog	Lu-ztj-gc90	1035225	984	Liss Charlton	HOW TO FILM AND EDIT TIKTOK/REELS MINI VLOGS|BEGINNER FRIENDLY
vlog	KdsWzPMCv7w	1024283	951	Jeven Dovey	How To Vlog and Be a Better Storyteller
vlog	C4OaVLNk8F8	868203	714	mmiakim	How to start vlogging with JUST your phone! | Tips for Filming, Editing, and More! 📱🎀
vlog	9b4MMGqclPI	800806	519	YT DADA	How to Create Mini Vlog? Shooting to Editing Tutorial | YT Dada
vlog	zVMzBUQ-pUk	777854	788	Shiny Days	☁️How to start making Aesthetic Vlogs with JUST your phone📱 filming & editing, tripods, VLLO app,…🧸
vlog	8AUPb4nQ4EI	686469	1095	tapiocapress	how to edit aesthetic vlogs (FULL workflow + tips to save time) beginner friendly
vlog	ng4v6MHxNFU	675289	1296	Dani Lee	what I've learned creating better vlogs & how I edit for youtube
vlog	-tg30y9FzHM	547207	564	Adobe Video	Best Video Editing Style for Travel Vlogs | Premiere Pro Tutorial with Kara and Nate | Adobe Video
vlog	vfHt3iXRGOE	504910	569	gaby rose ⭑	how i film + edit a minivlog | day in the life, filming bts, capcut editing, tiktok/reels tips
vlog	WTFqPvc7luE	326856	1161	Best360	10 Easy Insta360 X5 Shots For A Travel Vlog Video In Hong Kong And Insta360 App Editing Tutorial
vlog	AbNmaVD38Z0	315269	1917	Ankit Bhatia	How to Edit Crazy Cinematic INTROs for Travel Video | Editing Breakdown
vlog	xMELGvNgSus	286892	667	Anastasia’s Vlogs	MY FAMILY SITUATION & HOW I EDIT MY INSTAGRAM PHOTOS!
vlog	k5htPAyGenw	262639	428	Mehry Vlogs	How To Edit Vlogs In Mobile | CapCut Main Vlogs Edit Krny Ka Tariqa | Mehry Vlogs |
vlog	K0tfyT61kks	257513	894	Technical View	How to Edit Vlogs in Mobile? Vlog Edit Garne Tarika KineMaster
vlog	DbTKAqzR2w4	242201	520	FXhome	Create Better Travel Videos with these Editing Techniques
vlog	MolCuBpbbS0	236688	192	Editing stage	How to Edit Cinematic Travel Video on Smartphone with VN video editor | Quick Tutorial
vlog	Zjif8sfSj2s	226441	1198	Learn Online Video	How To EDIT a Cinematic Travel Video
vlog	NTGWV64knXA	189777	813	HillierSmith	HOW TO MAKE A DAVID DOBRIK VLOG - Video Editor Reacts
vlog	mPcGxk0tDJc	178392	1527	Lost LeBlanc	How To Make a TRAVEL VIDEO - 5 Steps to BETTER Editing
vlog	ZZmxSU8vriI	175862	1744	Vanessa Lau	How to Film + Edit Voiceover Vlogs | day in the life, gear, filming bts, editing + more!
vlog	Yp3tjKqcWCQ	173505	926	Minoli Disanayaka	How I film & edit my videos මම vlogs කරන විදිහ aesthetic vlog tutorial for beginners #vloggingtips
vlog	skawgTWY8hM	133518	482	Lila	how to edit vlogs
vlog	R8o3yH3LGgk	124474	356	Esha's attic	How I Vlog With JUST My Phone (FACELESS) 🎧🖇️ + Editing Tips
vlog	xKX0cOo1r6M	119972	1571	Content Creators	How To Edit Viral Travel Tik Toks & Reels using CapCut
vlog	7nNaWpMmiIk	91468	1489	Katie Steckly	How to Edit Your First Vlog Without Feeling Overwhelmed
vlog	V4ZaGyXC6KA	68999	753	Kritika Goel	How I Edit My TRAVEL VIDEOS! (Organizing, Editing, Music, Transitions + MORE)
vlog	cWu2aQhHe1Q	66619	410	Kane and Pia Muehlenbeck	HOW TO EDIT A VLOG (Part 4: Final Cut Pro basics for efficient editing)
vlog	-knzYbKyBf4	53060	899	Evan Lindy	How to edit Vlogs LIKE A PRO!
vlog	EA9riVpKvHg	49847	2902	Joey Edits	how to edit vlogs for Youtube in Capcut PC - Beginner Tutorial
vlog	60I2AkoMqKI	49557	1319	Laura Jane Illustrations	Vlogging tips for beginners ✨ How I plan, film + edit DITL vlogs
vlog	dcA6CWXAKpQ	40393	1589	Modern Millie	How to Film + Edit Vlog-Style YouTube Videos (everything beginners need to know)
vlog	GGlgqSbzA8c	36265	925	Pascal Basel	Travel Video Editing: 5 Techniques for Cinematic Vlogs
vlog	BXatSHBAz1Q	35346	998	dyidyi	how to edit aesthetic day in my life silent vlog in capcut in 2025 ― beginner friendly and tips
vlog	miML2hkmO1o	33928	1840	Mohnish Doultani	How I Edit Cinematic Travel Videos | My Editing Workflow and Tips
vlog	LE0l30uoNaM	21785	1066	Katie Steckly	Beginner guide to editing vlogs (that grow your channel!)
vlog	h3pFOsaoEtY	17368	543	Adelaide Ann	How I Edit My Mini Vlogs on CapCut (Step-by-Step Tutorial)
vlog	hJk8iwyRSio	17304	600	World Wild Hearts	HOW TO EDIT TRAVEL VIDEOS | Beginners Guide
vlog	D_V6x5V-Quk	15008	497	Jayden Choi	How to make aesthetic TikTok vlogs | CapCut, Filming/Editing tips
vlog	AIA3t44myXA	14518	1556	Boy Perstaym	THIS IS HOW I EDIT MY VLOGS! (Editing & Storytelling Tutorial)
vlog	fcL49CI2pM4	13274	3081	Roadside Traveller	Travel Vlog Editing Masterclass | class 00
vlog	uT-JaU9MMy4	13243	905	Londyn Guidry	How I Edit My Vlogs as a Teen Content Creator | vlog tips, editing, summer school
commentary	Ex1R3rsdlms	1317766	2147	Content Creators	Edit PRO Youtube Videos in Capcut
commentary	xl-WDjWrTtk	789623	1292	Pat Flynn	How to Record and Edit a Podcast in Audacity (Complete Tutorial)
commentary	LxAxV6Eg8mo	654507	325	Social Sunil	🎙️How to make Podcast Shorts? Shorts Editing Tutorial
commentary	J0oKsStLblE	439571	1437	Jonny Shapland	How To Edit Viral Podcast Clips - Exposing TikTok Guru SECRETs for FREE… (Video Editing Guide)
commentary	uTNnpkpYr0A	352143	1738	Joe Sbiti	How To Make VIRAL Podcast Clip Videos
commentary	YX8HT0sZ9Lo	233927	505	Think Media	How To EDIT and EXPORT Video Podcasts (Beginner's Guide)
commentary	Y3jHCcXUfoM	201541	476	Levi Allen	How to Edit Interviews
commentary	xCl_zqJdjAc	194546	669	Think Media	How to Edit Talking Head Videos: 5 Video Editing Tips & Tricks
commentary	HQvV75kjblY	192549	1037	Joseph | Video Editing	How to Edit Viral Instagram Talking Head Videos (New Style 2026)
commentary	7hHyY2HhHf4	192473	1154	The Editing Podcast	How To Edit Talking Head Videos
commentary	xeng_HQjLIE	157145	517	Krish	How I edit viral commentary shorts with Claude AI and CapCut
commentary	X_2gjhfJqrg	124472	609	ChatCut	How to Edit Videos: Talking Head Editing Tutorial for Beginners
commentary	FvhgJSWQ4ps	119286	1721	Joseph | Video Editing	How to Edit Viral Talking Head Videos Like Devin Jatho (2026 Guide)
commentary	h7vPja2Eufs	117198	248	Gavin Herman	How to Automatically Edit a Podcast in Premiere Pro (It Takes MINUTES!)
commentary	pUwVGWWKcHc	112212	490	Riverside	How To Edit A Podcast (For Beginners)
commentary	70qOJfizZjM	95376	1478	Standard Story Company	How to Edit 2 Camera Interviews Like a Pro
commentary	7D32yx4i-HE	93684	398	DBD™	Quick Tips for Editing Interviews
commentary	_KHLViV5eKo	88435	297	Magnify Freak	How to Edit Podcasts in Premiere Pro: Learn Podcast Editing in 5 Minutes!⚡⚡
commentary	6_jokOm1mIk	83301	199	Aman Guides	I Found the SECRET to Edit Talking Head Videos Like a PRO (Ultimate Guide)
commentary	Z2z514tcwpc	68267	500	indietrix	How To Make A Video Essay: Editing
commentary	KvsdRYzZ8ps	67422	409	Brooker Films	How To Edit an Interview
commentary	dumGc0TzCpY	58610	698	Cory Malveaux	Edit Podcasts Like a PRO! CapCut Multi-Cam Editing Tutorial
commentary	q-qbKk8Qams	55860	1791	BeTheCut	How To Edit TALKING HEAD REELS from scratch in CAPCUT | FULL EDITING BREAKDOWN
commentary	4ckmTzuDoNA	54594	2495	Dave Dugdale	Editing Interview Footage - Tips and Techniques
commentary	aNwKDaTag2Q	49347	1534	TomsProject	How to Edit Viral Talking Head Videos Like Kallaway (2026 Guide)
commentary	hBv7C9eixLg	43036	260	Rishabh Sharma	How To Edit Podcast In Capcut? | Simple Steps | Multi Camera Editing In Capcut
commentary	-nHNMjCyx94	42411	593	SD BIO	SLST Edit Problem & Verification Interview and WBSSC Group C D Recruitment Rules । SSC Gr CD Result
commentary	IXsR54AY4i8	40993	541	Riverside	Edit A Video Podcast For Free | DaVinci Resolve Tutorial
commentary	tmlYRUTlA6A	39471	968	PSS Creative Media	How to Start a Video Podcast in 2026 (Studio, Gear, Editing & Distribution)
commentary	OFyb0zesfhI	37047	384	The Nicks Edit	How I Edit Trending Podcast Reels in Premiere Pro | Full Breakdown
commentary	RXQOmQGJK34	36906	2007	Hishaam Ahmed	How to Repurpose Podcast into Shorts | DaVinci Resolve Advance Reel Editing Tutorial
commentary	lo2T9eMFKNA	36416	992	Riverside	Video Podcast Editing Made Simple: Full Tutorial for Beginners
commentary	HpZ8JCpOEn8	36102	681	John Hague	How To Edit A Talking Head Video (The Actual Principles)
commentary	scJab5Rk6Dk	34829	602	Jam Punch Storytelling	7 Interview Editing Tips in Final Cut Pro, Tutorial
commentary	LZdDqbqocAI	28933	640	moneyboymax	How To Edit VIRAL Caption Commentary Shorts
commentary	hdwG7FIc2EM	28781	666	MikeZunigaFilms	How To Edit An Interview In Premiere Pro (For Beginners)
commentary	92VW0bfmrGs	24645	299	Corey Machado	How to Edit an Interview in Adobe Premiere Pro
commentary	wkWkHwFKcNE	22745	747	Vlad Sateev	How to Edit Viral Talking Head Reels in Premiere & After Effects
commentary	DQO0xJudELM	22106	894	Think Media	How To RECORD and EDIT A Podcast For Beginners!
commentary	EsGEP7eY7mE	21881	524	Cynthia Patrick | CeemediaAgency	How to Edit Professional Talking Head Videos in CapCut (Step-by-Step Tutorial)
commentary	1WGYoG-qfqk	21717	1941	Matthew Padilla	How to edit INTERVIEW videos using CapCut for FREE!
commentary	m-18bJSouYI	21204	761	Riverside	How To Edit A Talking Head Video (7 Easy Steps)
commentary	BVaoIVm1DFo	20667	1099	Podcasting with Hiwi G	Complete Podcast Editing Tutorial for Beginners
commentary	6JcrJzLOe-g	18585	699	Denz Creates	How to Edit Your Talking Head Videos (Fast, Clean, Professional)
commentary	BwIE7YVbEgM	16494	270	Rishabh Sharma	How To Edit Podcast In Premeire Pro - Simple Steps (Beginner's Guide) | Multi Camera Editing
commentary	3v4N4BwNnvk	14603	560	Oskar's Editing Lab	How To Edit A Podcast Intro Like Steven Bartlett’s “Diary Of A CEO” (Premiere Pro Tutorial)
commentary	QC6KHm09ErY	14493	3305	Sweno Creative	How I Edit Podcasts in DaVinci Resolve (Fast + Easy Workflow)
commentary	BYiF8y317Jo	12086	912	Collin Michael	How To Edit Talking Head Videos Like A Pro!
commentary	y7GoUICupVM		295	Olufemii	Cutting Talking Head Footage is a Science
cinematic	3mZuJAWH1Ow	5732509	617	Daniel Schiffer	How I Plan Shots & Transitions | B ROLL 101
cinematic	Wv3Hmf2Dxlo	4707981	321	Shutterstock Tutorials	9 Cuts Every Video Editor Should Know | Filmmaking Tips
cinematic	OAH0MoAv2CI	4542293	701	RocketJump Film School	Cuts & Transitions 101
cinematic	gnWHHxr6TVs	3027347	311	FILM CRUX	13 Mindblowing Video Editing Tips (with CapCut on Desktop?)
cinematic	5QUSuMPD95k	2284694	600	Joris Hermans	How to Edit a Cinematic Video in CapCut
cinematic	Dhj8fnodWCE	2259546	540	Learn Online Video	8 Smartphone Gimbal Transitions | Mobile Filmmaking Tips For Beginners
cinematic	pAh83khT1no	2215021	1062	Film Riot	Color Grading 101 - Everything You Need to Know
cinematic	FVR8zz8ci2k	1895281	1128	StudioBinder	6 Ways to Edit Any Scene
cinematic	Lf5SSJw3HGQ	1854470	526	Bryan Adam Castillo	how i FILM, EDIT & COLOR GRADE iPhone CINEMATIC MODE video!
cinematic	fS3OLf0coDg	1797996	493	Edit with Bk	Instagram CINEMATIC Text Video editing in mobile | Capcut video editing | A Complete Tutorial
cinematic	Ehvh5adVqMo	1697285	1017	This Guy Edits	Lessons from the Top Film Editors
cinematic	qSMi0ygL--E	1663597	823	Daniel Schiffer	EDITING BREAKDOWN | EPIC B ROLL
cinematic	TKXBAaQB03U	1482526	1169	StudioBinder	Ultimate Guide to Scene Transitions – Every Editing Transition Explained [The Shot List, Ep 9]
cinematic	D-cKmLBdTL8	1440192	694	lacapturevisuals	How to make ANY video CINEMATIC
cinematic	xrjtPkSG5ug	1426616	1082	S M Tech	How To Edit Like Cinematic Video In Capcut | Trending Cinematic Reels Editing Full Tutorial🔥
cinematic	JoNT_kob3-8	1388494	471	Enam Alamin	Cinematic SOUND DESIGN Tutorial for FILMMAKING
cinematic	pdLEHfkwgV8	1342875	314	Andrew	The Power of SIMPLE Editing
cinematic	YtULPT1aBWM	1335969	344	Jonny Duncan	10 Editing Cuts Every Video Editor Should Know
cinematic	TMnBLZy3WFg	1314012	600	Joris Hermans	FAST, EASY & FREE! Cinematic Color Grading in CapCut | Video Editing Tutorial
cinematic	eXq0jY-cQmY	1224757	454	Kunal Malhotra	Color Grade Videos in Mobile Like a PRO - VN Editor Tutorial
cinematic	1wZym4fQGig	1185370	815	Zac Watson	Adobe Premiere Pro Color Grading Tutorial
cinematic	jgYg0LfFUI4	1177851	1242	Peter McKinnon	HOW I EDIT B ROLL & SOUND DESIGN
cinematic	zXF0kfePL60	1143811	600	Collin Michael	How To Edit CINEMATIC VIDEOS in CapCut (Ultimate Guide)
cinematic	BRcvU5GxmE4	1138179	1128	Peter McKinnon	How to Make a CINEMATIC Short Film! (Live Editing / BTS)
cinematic	Wcxw3BPSt3A	1114978	1026	Film Editing Pro	How to SOUND DESIGN a Video | Step-By-Step Tutorial
cinematic	tzfzkTAQsnE	1087869	442	Herman Huang	3 Sound Design Secrets That Feel Like CHEATING
cinematic	5hJOdQ1zhX8	1082870	792	Daniel Schiffer	How I Edit Smooth Transitions! | Coffee B ROLL Walk-through
cinematic	gtF8D8OQDQA	966144	958	Editing Edition	Color Grade Any Video in 15 Minutes – DaVinci Resolve Masterclass | Full Beginner Series – Part 5
cinematic	_KImTKhy_mI	796319	1203	Declan Jenkinson	Colour Grading For BEGINNERS (DaVinci Resolve Tutorial)
cinematic	8LV1bqf8ZVo	796300	1132	Artlist	How To SOUND DESIGN | Step by step tutorial
cinematic	yVfbV-UYrOY	684219	211	PlanetEris	How to Edit Cinematic Video Using CapCut | Color Grading
cinematic	Fu3vhFlXV0w	673638	245	Pond5	13 Creative Film and Video Editing Techniques
cinematic	zWK_in85mYY	535121	483	Collin Michael	Cinematic Editing in CapCut: Create Hollywood Style Videos! (Tutorial)
cinematic	J7-r4ouPmwE	522884	1591	Modern Millie	THE ULTIMATE TIKTOK TUTORIAL FOR BEGINNERS | How to film, edit and set up your account for success
cinematic	RN5fe77N598	475331	933	Best360	Insta360 X4: How To Film And Edit 15 Easy Shots In Istanbul For A Travel Vlog Video
cinematic	c0YINYT4Ozw	449253	1599	Skymography	How To Sound Design ANYTHING.
cinematic	5h12LYZlvzI	448702	729	Joris Hermans	Cinematic Color Grading Made EASY! | DaVinci Resolve 18 Tutorial
cinematic	sJLldZdGkzA	444396	839	Zane Hoyer	How to Edit Cinematic Animations in DaVinci Resolve
cinematic	ABK0S0rzyQk	416068	629	PremiumBeat by Shutterstock	Cinematic Color Grading in Final Cut Pro – Step-by-Step Tutorial
cinematic	_6kBvkjdZ7g	399451	1047	Ryan Herrick	How I Film & Edit Client Reels In DaVinci Resolve (Full Breakdown)
cinematic	wPbfaIJEBtk	387815	578	Jayanta Bhai	Cinematic Video A to Z Editing Tutorial | Capcut App Cinematic Video Editing | Capcut Edits
cinematic	ZfDpg78OD6g	379871	481	Mridu Mousam Neog	Edit like a PRO: Cinematic Editing Breakdown
cinematic	1-5mXPEsm3k	371630	1254	KC ian	Create Your Film Grade in DaVinci Resolve – The Ultimate Cinematic Color Grading Tutorial
cinematic	066tDE9AT-A	343914	1035	Jaydee Alberto	Make your Videos look like Film | Color Grading Tutorial | QUICKFILM x DEHANCER
cinematic	pWIMTqVNdTY	340861	630	Abhay PS Rajawat	10 Cuts Every Video Editor should know !
cinematic	vXc56AMPigA	321324	250	Adobe Video	Everything You Need to Know to Edit a Short Film | Premiere Pro Tutorial w/ Cinecom | Adobe Video
cinematic	UjkZomxXAL0	313108	1859	NSB Pictures	Learn Cinematic Sound Design in 30 Minutes - Masterclass
cinematic	a9reuDw4cnU	295452	1024	StudioBinder	How to Pace Your Film — Examples of Good and Bad Pacing in Editing, Writing and More
cinematic	VcorFuUmOBI	283686	885	Garrett Sammons	Film Better Dialogue With One Camera! | Shooting & Editing Tutorial
cinematic	FnBSg6YOFNY	270031	504	Mediabee Color Lab	DaVinci Resolve Secrets for a Cinematic Look | A Step-by-Step Color Grading Workflow #Tutorial
cinematic	neIBfxJ8JFo	264625	548	Abhay PS Rajawat	How I make my Cuts SO smooth, they become Invisible.
cinematic	FjpnOstqBvs	232759	656	Abhay PS Rajawat	Complete Guide to Sound Design any Video like a PRO
cinematic	bxAdCSL-n5E	228470	423	Herman Huang	3 Sound Design Secrets 90% of Editors Don't Know
cinematic	CoWY1uOZqOY	216101	472	Tolu Travels	How to film AND edit high quality Youtube videos on your Iphone in 2025
cinematic	nr_0BRqT0Qg	204937	245	Made in Hollywood Teen	'Interstellar' Editor Lee Smith on How to Edit a Scene
cinematic	1A1P4mHs1qY	201760	2516	Content Creators	How to Film & Edit Cinematic TikTok Videos & Reels
cinematic	2_zNSfpi5IM	191793	464	The Rdx Prince	CapCut Cinematic Video Editing Tutorial | A to Z CapCut Cinematic Edit for Beginners (2025)
cinematic	PKYeClvvlTw	188862	905	StudioBinder	The Book Every Editor Has to Read — Walter Murch and In the Blink of an Eye
cinematic	Kc-Hx9US3lE	185122	391	Creative Graphicz	Smooth Transition Edit with Free Effects | FIlmora 12 Tutorial
cinematic	eIp6F1wbIIo	180325	622	Jacques Crafford	Sound Design for Filmmaking - CINEMATIC VIDEO Tutorial
cinematic	3VszXdrCi6A	153863	563	StudioBinder	Thelma Schoonmaker & Scorsese — Film Editing Tips from Goodfellas, Shutter Island, and The Irishman
cinematic	QTEN6MUMCPI	152674	786	Enam Alamin	Pro Color Grading Workflow in Premiere (8 Cinematic Steps)
cinematic	tPQ2PvO8USk	149470	662	Matthias Dangl	10 TRICKS for Cinematic SOUND DESIGN - Premiere Pro Tutorial
cinematic	yaqq9aB1csw	144323	682	FilmSkills	How To Shoot & Edit Dialog Scenes - Part 1
cinematic	sh5MEb5cX1M	135427	946	Joris Hermans	FAST, EASY & FREE! How to Edit a CINEMATIC Video in DaVinci Resolve 19 [Beginners Tutorial]
cinematic	pvdhQnetu9o	134806	394	AniThing	How to Control PACING in Your VIDEOS
cinematic	caWge0sQqzw	133570	1175	Standard Story Company	How to Sound Design a Short Film
cinematic	xUK64UkTmW0	128184	372	StudioBinder	How to Use Walter Murch's Eye Trace to "Direct the Eye" with Cinematic Editing #filmeditingtechnique
cinematic	Udo472sNpnU	126092	830	Jayanta Bhai	How To Edit This Viral Cinematic Reel In Capcut | Cinematic Video Editing | Capcut Tutorial
cinematic	5o0Z2CvFXhM	122310	495	Becki and Chris	Tips For Editing a Cinematic B-roll Sequence
cinematic	oWXJXXrOxD4	119087	737	Film Editing Pro	Montage Editing 101 (TUTORIAL)
cinematic	9jBic4IDfxA	117494	898	Gavin Herman	How To Sound Design ANY Video In 15 Minutes
cinematic	BlgYzBqaltQ	114494	491	Abhay PS Rajawat	Cinematic Video Editing for Complete Beginners - Step by Step Guide for Filmora 15
cinematic	eraB3u3e7aM	110809	566	Abhay PS Rajawat	How to Control PACING in your Video Editing
cinematic	btaepb3ioRI	110048	539	Casual & Woodstock	How to Edit Videos Like a Cinematic Beast
cinematic	zK-S_ZCdeQE	105683	247	Cutting Concepts	The Rule of Six: A Guide for Masterful Film Editing
cinematic	oie7yQgMzVw	103067	601	Chris Shaw	How to: Editing Film Dialogue
cinematic	b2apifGyhuQ	102580	1241	Zdenka Darula	How to FILM & EDIT with SAMSUNG GALAXY S24 ULTRA | CINEMATIC B-roll
cinematic	0_Sakq2LdL8	99277	710	Moonbow	The Easiest Way to Get the FILM LOOK in Davinci Resolve 20 | Color Grading Tutorial
cinematic	zP7UReyzIOE	97629	453	The Metaverse Guy	ElevenLabs SFX v3 Tutorial: How to Sound Design with AI - Turn Text Into Cinematic Sound Effects
cinematic	W0ssQOv7s4c	96030	844	Aidin Robbins	How to Nail the PACING of your Travel Film - Video Editing Tips
cinematic	R3PZX5pjo5w	91096	623	Foot Prints	HOW TO EDIT A PROFESSIONAL SHORTFILM 2020🔥 | VIDEO EDITING TUTORIAL
cinematic	9gEpqrX-FW0	87955	733	The Film Look	5 Essential Editing Tips for Short Films!
cinematic	6OQHNez-dIg	81508	689	Team 2 Films	Ultimate MUSIC Editing Guide - Beat Match and Ring Outs - DaVinci Resolve Tutorial
cinematic	t35QziibejM	78664	189	Premiere Basics	4 CUTS Every Editor NEEDS To Know! (Premiere Pro Tutorial)
cinematic	CdyTIng0M8Q	69263	785	Inside The Edit	Pacing in Film Editing: Techniques Every High-End Editor Must Know
cinematic	6mvjS-sl39E	67389	1032	This Guy Edits	Film Editing Techniques - How to Edit a Scene
cinematic	H5OulRPhxEg	66403	775	Digifilming	10 Essential Editing Cuts Every Filmmaker Should Know | Film Editing Tips
cinematic	OagnZAD_9wY	64096	1507	Alex Zarfati	Cinematic Sound Design for Filmmaking | Full Tutorial
cinematic	HbPgJidesEI	63905	248	Wondershare Filmora Video Editor	5 Film Editing Cuts Every Editor Should Know!
cinematic	IG683SXcal4	62257	201	Film Editing Pro	Video Editing Pacing Tips
cinematic	Sg-PkeMv_Bs	60300	2098	Trevor Jones	How to Edit a Cinematic Video in CapCut
cinematic	YLzbwWumNe0	60053	399	Joey Edits and Joey Edits - Mobile	7 Must-Know Video Editing Cuts (And How to Do Them in CapCut)
cinematic	4Y9gIc3DnA8	57985	643	Film Editing Pro	Film Editing Techniques: Timing Your Cut to Enhance the Drama
cinematic	C00G7lWqIUA	57579	1424	chinfat	E25 - How to Edit Dialogue for a Movie Scene - Adobe Premiere Pro CC 2018
cinematic	uTVxZ5c5W0M	57019	1450	Film Editing Pro	How Great Editors Think Like Filmmakers (Scene Breakdown)
cinematic	jN3TIBIQlac	52555	675	Inside The Edit	How to Edit B-Roll Like a Pro
cinematic	n6uSGD5HZvk	39010	357	MADO	Start to Finish: How I Plan, Shoot & Edit My Cinematic Videos
cinematic	WkMPGZlc02c	36626	232	Daniel Batal	5 Cuts EVERY Video Editor Should Know!
cinematic	3-BJ9sMSlo4	36315	283	Dan - Smart Tutorials	CapCut Tutorial - 2026 | How to Use AI Dialogue Scene (Smarter Image Edits With Seedream 4.0)
montage	kmnYxvGxLVE	3103158	371	Gaku Lange	Slide Transition TUTORIAL - How to SPEED RAMP Creatively
montage	QTiTuerA0-c	1724724	408	Exal.Visuals	How to Make SMOOTH TWIXTOR + 120FPS Edits on CapCut | Beginner Guide ✨
montage	FWDtMRTmFII	1648158	381	90 Creators	AUTO BEAT SYNC 🔥 | How to Perfectly Beat Sync in Video | Edit Beat Sync by 90 Creators
montage	-7r0XC7k9L0	1266029	300	Vivian Shea	how to make a tiktok edit on capcut in 5 minutes! *beginners tutorial* velocity, transitions etc.
montage	K6leEKtC2kc	1172961	695	Milliam	How to Edit An INSANE Fortnite Montage like Flea / Milliam
montage	_1l7Jyssblg	1148563	458	SM Art	How to make auto velocity video edits in CapCut | Trending Instagram velocity reels edit
montage	wAEMDLc6E1M	1126556	915	Cudi Edits	How To Have "Flow" On Your Montage/Edit! (How To Make A Montage #1)
montage	NyzU6dv5v5c	1057260	252	x.Mariahh Edits	HOW TO MAKE A SMOOTH VELOCITY EDIT WITH ONLY CAPCUT ( NO VIDEOSTAR NO AFTER EFFECTS) *OUTDATED*
montage	n7uieO_hWqY	930869	400	Enam Alamin	Make the Smooth SPEED RAMPING Transitions without Gimbal (Step by Step)
montage	_77hOByZFA4	869788	745	Ka Production	Speed Ramp Video Editing In Capcut | Speed Ramp Transition Edit In Capcut | Capcut App Tutorial
montage	QAsThTVr4GQ	858739	373	Tech Editz	1410 Gaming Colour Grading Tutorial In Capcut || FreeFire Montage Shorts Editing Tutorial 🔥
montage	-2eXk0oLFQs	855609	234	Justin Odisho	How to Edit to the Beat | Cut & Sync Footage to Music in Adobe Premiere Pro CC for a Cinematic Feel
montage	qqIuLmGsfT8	835711	1343	spllitz	How to Make a COOL FORTNITE MONTAGE ON SHAREFACTORY! (EASY)
montage	JhxO_W--rfo	786604	443	KhannaFilmLab	Velocity Reels Editing Tutorial In Capcut | How To Create Velocity Video
montage	8IZrt0gpz_s	783929	1324	Yia Edits	How to Edit a *CLEAN✨* Valorant Montage Like Cjaiye on Davinci Resolve!!!
montage	zxw7LGGNLYY	766892	638	konradnoises	Edgar Wright - How To Edit To The Beat
montage	L_ol7O2xgqM	744207	671	SM Art	How to make Ultra Smooth Speed Ramp videos in mobile | Speed Ramp video editing tutorial
montage	2VhJgv1xGL8	696921	490	ShootaTime	My Secrets to SMOOTH Speed Ramps in After Effects!
montage	UDgKrsb1X7A	597248	759	Vaultcar	How To Actually Make GOOD EDITS - DaVinci Resolve
montage	yd02IVaqN-w	515398	1292	Rocklan	How to SYNC & FLOW Valorant Clips for Montages & Edits (Premiere Pro Time Remap Tutorial)
montage	lVYQkejspR8	481697	791	Gaku Lange	How to Speed Ramp like a PRO
montage	IXYO9zhVmwM	350713	1258	Rocklan	How to make a VALORANT MONTAGE like ZISHU! | Editing Tutorial
montage	kEoJTXSjxVE	313629	495	rdylt09	Velocity Edit Tutorial I After Effect's Guide
montage	flxiVDpVFi4	263617	1524	Rocklan	How to make a VALORANT MONTAGE like Ladiff! | Premiere Pro Editing Tutorial
montage	5wBPkKBpT6k	255943	1091	HOBO Ae	Full velocity edit tutorial on after effects
montage	y1Ew7clZYDQ	236422	365	Motion Array Tutorials	How To Create A Montage | 3 Helpful Tips
montage	_e0Pk65yPg8	217913	1048	Matt Loui	Viral Speed Ramp - Full CapCut Tutorial
montage	A-VIBvrgL_U	176472	183	DON CYR	HOW TO SLOW-MO/TIME REMAPPING/SPEED RAMP CSGO TUTORIAL (PREMIERE PRO)
montage	ao0amyX5JsE	169868	446	jayd3nfx	Simple Velocity Edit Tutorial (After Effects)
montage	bXx99Oh9Hoo	155566	231	NLT MoviePod	Learning about The Montage - Film Studies
montage	FZBcMg1V_d0	136816	1419	Rocklan	How to make CUSTOM CINEMATICS for CS2 Montages / Edits | 2 METHODS - HLAE & S2FM Tutorial
montage	kfsSIapzdN0	135921	577	Miracamp	How to get PERFECT Speed Ramp Transitions in Premiere Pro 2025
montage	g7xDHdamvUE	130652	351	Carson Bopp	How to edit a Fortnite Montage on CAPCUT in 5 steps!
montage	OALHSVUqPmg	128317	467	Creative Graphicz	How to Create a Viral SPEED RAMP Edit in Filmora 12
montage	A0dQd_EvsVA	121065	2514	Vityl	How to EDIT a PROFESSIONAL VALORANT Montage (AE)
montage	KRrQzRZ9UBM	114833	1951	pingu	how to make really good montages with no editing skill
montage	nLR7W66GCPo	112585	646	Alexander	CSGO Tutorial - How to make a FRAGMOVIE (1080p 60fps)
montage	TFJ-3Vc7z5Q	101666	328	KingSlayer06	TOP 5 EFFECTS to add to your MONTAGES | After Effects Tutorial
montage	CoM6G4Ebphs	95237	1696	Rocklan	How to CORRECTLY Record CS2 Replays for Montages and Edits! | HIGH FPS HLAE TUTORIAL
montage	JVaWA0mUzJI	93045	1347	Juan	How to Edit a FiveM Montage like a PRO
montage	Kt_BAN2YG_A	87976	1329	Rocklan	How to make a VALORANT MONTAGE like Cjaiye! | Smooth Editing Tutorial (Premiere Pro)
montage	tHJredIfdIA	86019	378	VIJAY GFX	Brazilian Players Montage Editing Tutorial 🤯 | Detailed Editing Breakdown
montage	S0VZYHfapcw	78118	317	Mat Vision	The SECRET to Perfect Speed Ramps
montage	WYqTvyXRZ-c	78092	541	Joshyy	How to EDIT Gaming Montages in 2024
montage	tsoc3-RwxI4	74193	436	akaazz	*UPDATED 2025* How To Make MONTAGES for Da Hood...
montage	7LhxcNe0ytY	70881	226	Cyanoodle	How To Make CSGO Look Sexy For A Fragmovie!!!
montage	JlPF19a2GuA	64539	233	Madzy	HOW TO MAKE AN AE VELOCITY EDIT ON CAPCUT MOBILE?!😨
montage	BuCt1JqlfmA	63418	705	Haruqie	BEST Effects For Valorant Montage/Edit [TUTORIAL]
montage	_lk3xK4ExUg	57951	1345	Rocklan	How to Import CS2 Demos into S2FM and Create POVs and Cinematics for Montages / Edits
montage	XHU7xMfbP5E	54470	501	Joshyy	How to Edit INSANE Fortnite Montages for FREE! | Davinci Resolve Tutorial (2024)
montage	uzGyS0a9Byc	51840	513	Brad West	How to Cut to the Beat | Tips for Editing to Music in FCPX
montage	YgrdUaHxGB8	49135	503	Azy - Content Creator	Velocity Effect Tutorial in CapCut | Video Editing Tutorial | Capcut Tutorial
montage	NM3cNGUyQQM	47722	1584	Rocklan	Top 5 Effects for Counter-Strike 2 Montages / Edits | Beginner's Guide
montage	9o4Grm0Z9c4	47123	1323	Nynevfx	Full velocity edit tutorial on after effects
montage	aIY2GYEi84M	35180	590	Joshyy	EDIT Gaming Montages Like a PRO for FREE! (Fortnite, COD, etc.) - Davinci Resolve Beginner Guide
montage	HDSjZZ80hyo	35173	2185	TUF	How to Make a CS2 Frag Movie in Unreal Engine Nikki HD, Fuze & PopWow Style
montage	ROJgCDcL1gk	33706	857	Cory Malveaux	Viral SPEED RAMP Motion in CapCut | Complete Step-by-Step Tutorial
montage	I_Zetvrr-rw	33629	620	fraud	How to edit *DA HOOD MONTAGES* (effects and stuff)
montage	K5M0S_gszrQ	28762	553	Jason Roberts Video	2 ways to EDIT to the BEAT in DaVinci Resolve 19
montage	qF7ukvCWAUo	27911	491	Vic Barry	How to edit a montage like a Filmmaker! Pro Tips!
montage	KV1ws64459c	26581	590	Vaultcar	How To Shoot & Edit Speed Ramp Videos - DaVinci Resolve
montage	ByZ6vHSeX5A	26476	576	MagnnuM	CS2 fragmovie tutorial - Beginner
montage	xXfLqFDwfRc	25926	737	OT Nytex	How to edit an INSANE Fortnite Montage like Flea & Milliam
montage	np00aZoiBfg	25873	503	Joshyy	How to EDIT Gaming Montages for Beginners! | Adobe After Effects Tutorial
montage	tBe-GVVFoiI	24821	588	VEED STUDIO	How to Make a Video Montage - Online Video Editing Tutorial
montage	Qn6BBRONH5w	23254	471	𝓒𝓵𝓮𝓪	Velocity Tutorial | Smooth Velocity Edit in After Effects
montage	cM-hhJneXAM	22956	1138	Rocklan	How to edit 3D Bullet Effect in Blender for your Montages / Edits!
montage	P-NL4ubEDV8	21083	493	Bralexanic	DETAILED GUIDE on How To EDIT Minecraft Montages
montage	lXT214ud3Js	20196	757	Exille	(EASY) How To Make Fortnite Montages Using CapCut | 2025
montage	BZhvXh7z9ec	18961	445	Lionz	How to Edit a Fortnite Montage in 2025 (FOR FREE)
montage	16tFJfBy1Jg	17578	413	AM Film	The SMOOTHEST Multi Speed Ramp Edit | After Effects Tutorial
montage	hNwxFATWndE	15823	572	Joshyy	Edit PRO Gaming Montages for FREE! | Davinci Resolve Tutorial (2025)
montage	-Lk3Z_cQG4o	14563	819	Zayy	How to Edit CPvP Montages
montage	D3PMT-eoJGI	14011	700	WombleFX	How to Make a COD Montage in Davinci Resolve Tutorial #1💸 (Tutorial)
montage	9rNe-BUJNKM	13995	1009	Yume	How To Edit A Gaming Montage \\ Davinci Resolve No Plugins \\ Basics Editing Tutorial
montage	MiDH__rv84U	13686	927	izmi31	Advanced Velocity Edit Tutorial | After Effects
montage	06zbVE7U7Cg	13296	813	GameFrame Evolution	Tutorial:TOP 5 Effects for Valorant Edits/Montages With CAPCUT Not AFTER EFFECT
montage	sSd5mIoCq88	12135	182	DON CYR	HOW TO SLOW-MO/TIME REMAPPING/SPEED RAMP CS2 TUTORIAL (Premiere Pro/After Effects)
montage	3YTRnW5PeKs	11689	550	Football Highlights	How to Make a Sports Edit with iMovie - Full Tutorial (Better Version)
montage	PQvmMCw-eNA	11510	1744	editedbysticky	*NO PLUGINS* How To Edit A Fortnite Montage With NO PLUGINS in Davinci Resolve
montage	5G5mZNzbb-k	11123	241	Wondershare Filmora Video Editor	How to Use Speed Ramp Like a Pro (Filmora Editing Tips)
montage	GaIGE3FWUJA	10587	254	Merle Becker	How to Edit to the Beat Using Markers in Adobe Premiere 2025
"""#
}
