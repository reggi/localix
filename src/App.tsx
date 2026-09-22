import release from './release.generated.json'
import './App.css'

const repository = 'https://github.com/reggi/localix'
const icon = `${import.meta.env.BASE_URL}localix-icon.png`

function DownloadIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path d="M12 3v12m-5-5 5 5 5-5M5 16v4h14v-4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function App() {
  return (
    <>
      <a className="skip-link" href="#main">Skip to content</a>
      <header className="site-header page-width">
        <a className="wordmark" href="#main" aria-label="Localix home">
          <img src={icon} width="32" height="32" alt="" />
          Localix
        </a>
        <nav aria-label="Main navigation">
          <a href="#how-it-works">How it works</a>
          <a href={release.releaseUrl}>Releases</a>
          <a className="source-link" href={repository}>GitHub <span aria-hidden="true">↗</span></a>
        </nav>
      </header>

      <main id="main">
        <section className="hero page-width" aria-labelledby="hero-title">
          <div className="hero-copy">
            <p className="eyebrow"><span className="status-dot" /> MADE FOR YOUR MAC. KEPT ON YOUR MAC.</p>
            <h1 id="hero-title">Your voice.<br /><span>Your Mac.</span></h1>
            <p className="hero-description">A little menu bar app that turns speech into text. Dictate into the app you’re using, with recognition that stays on your device.</p>
            <div className="hero-actions">
              <a className="button button-primary" href={release.downloadUrl}>
                <DownloadIcon /> Download for Mac
              </a>
              <a className="text-link" href={release.releaseUrl}>What’s new <span aria-hidden="true">↗</span></a>
            </div>
            <p className="download-meta">{release.version} <span aria-hidden="true">·</span> macOS 13+ <span aria-hidden="true">·</span> Apple Silicon</p>
            <p className="download-note">Free &amp; open source. <a href="#install">First time installing?</a></p>
          </div>

          <div className="product-scene" aria-label="Illustration of Localix recording from the menu bar">
            <div className="scene-toolbar" aria-hidden="true">
              <span className="scene-app">Your workspace</span>
              <img className="menu-recording" src={`${import.meta.env.BASE_URL}localix-recording.png`} width="30" height="24" alt="" />
              <span className="scene-time">9:41</span>
            </div>
            <div className="note-window">
              <div className="note-titlebar" aria-hidden="true"><span /><span /><span /><p>A little less typing</p></div>
              <div className="note-content">
                <span className="note-label">A THOUGHT, CAPTURED.</span>
                <p>Some ideas are<br />easier said<br /><span>than typed.</span><span className="cursor" aria-hidden="true" /></p>
                <div className="note-rule" />
                <span className="note-footnote">Room for your next idea.</span>
              </div>
            </div>
            <div className="recording-card">
              <img src={icon} width="48" height="48" alt="" />
              <div><strong>Localix</strong><span>Recording on this Mac</span></div>
            </div>
            <p className="scene-caption">In your menu bar. Out of your way.</p>
          </div>
        </section>

        <section className="principles page-width" aria-label="Why Localix">
          <article><span className="feature-number">01 / PRIVATE</span><h2>Your words stay yours.</h2><p>Uses Apple’s on-device Speech framework. No cloud transcription and no audio uploads.</p></article>
          <article><span className="feature-number">02 / SIMPLE</span><h2>Speak where you work.</h2><p>Focus a text field, start recording, and speak. Localix types into the app you’re using.</p></article>
          <article><span className="feature-number">03 / IN YOUR CONTROL</span><h2>A shortcut to your thoughts.</h2><p>Hold to record or press to toggle. Pick your microphone and set your own keyboard shortcut.</p></article>
        </section>

        <section className="how-section page-width" id="how-it-works" aria-labelledby="how-title">
          <div className="section-heading"><p className="eyebrow">LESS SETUP. MORE SAYING.</p><h2 id="how-title">One small app.<br />Three simple steps.</h2></div>
          <ol className="steps">
            <li><span className="step-number" aria-hidden="true">1</span><div><h3>Make yourself at home.</h3><p>Download the ZIP, unzip it, and move Localix to Applications. Open it and look for the speech bubble in your menu bar.</p></div></li>
            <li><span className="step-number" aria-hidden="true">2</span><div><h3>Give it permission to help.</h3><p>Allow Microphone and Speech Recognition, plus Accessibility so Localix can type for you. Custom shortcuts also need Input Monitoring.</p></div></li>
            <li><span className="step-number" aria-hidden="true">3</span><div><h3>Find your words.</h3><p>Focus a text field. Click the menu bar icon or hold <kbd>Right Option</kbd> and speak. Click again or release the key to stop.</p></div></li>
          </ol>
        </section>

        <section className="install-section page-width" id="install" aria-labelledby="install-title">
          <div className="install-intro"><p className="eyebrow">A COUPLE OF THINGS TO KNOW</p><h2 id="install-title">Hello, macOS.</h2><p>Localix is a small independent, open-source app. Here’s what to expect on your first run.</p></div>
          <div className="faq">
            <details open><summary>macOS says the app can’t be opened.</summary><p>The download is ad hoc signed, not Apple-notarized. After trying to open it, go to <strong>System Settings → Privacy &amp; Security → Open Anyway</strong> and confirm. Only do this for a download you trust. An update may need approval again.</p></details>
            <details><summary>Does it send my speech anywhere?</summary><p>No. Localix requires on-device recognition. If it isn’t available for your current macOS language, the app stops rather than sending audio to a server. History contains session metadata, not transcript text or recordings.</p></details>
            <details><summary>Which Macs does it support?</summary><p>Localix is intended for Apple Silicon Macs running macOS 13 or later, with on-device speech recognition available for the current language. Intel compatibility has not been verified. The download contains an Intel build, but that does not guarantee the required on-device recognition is available.</p></details>
            <details><summary>Can I see the code or verify the download?</summary><p>Yes. Localix is <a href={`${repository}/blob/main/LICENSE`}>MIT licensed</a>, and the source is <a href={repository}>on GitHub</a>. The <a href={release.checksumUrl}>SHA-256 checksum</a> is published alongside each download.</p></details>
          </div>
        </section>

        <section className="closing page-width" aria-labelledby="closing-title">
          <img src={icon} width="64" height="64" alt="" loading="lazy" />
          <div><h2 id="closing-title">Let your voice do the typing.</h2><p>A little more flow. A little less keyboard.</p></div>
          <a className="button button-primary" href={release.downloadUrl}><DownloadIcon /> Download for Mac</a>
        </section>
      </main>

      <footer className="site-footer page-width">
        <p>Localix <span aria-hidden="true">/</span> Small by design. Local by default.</p>
        <div><a href={repository}>Source code</a><a href={release.releaseUrl}>Release {release.version}</a><a href="https://github.com/reggi">By reggi</a></div>
      </footer>
    </>
  )
}

export default App
