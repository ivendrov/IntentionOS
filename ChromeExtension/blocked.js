// Parse URL parameters
const params = new URLSearchParams(window.location.search);
const blockedUrl = params.get('url') || '';
const intentionText = params.get('intention') || '';

// The phrase to type (should match the Swift app config)
const BREAK_GLASS_PHRASE = 'I am choosing distraction';

// Populate the page
document.getElementById('blocked-url').textContent = blockedUrl;
document.getElementById('intention-text').textContent = `"${intentionText}"`;
document.getElementById('break-glass-phrase').textContent = BREAK_GLASS_PHRASE;

const phraseInput = document.getElementById('phrase-input');
const continueBtn = document.getElementById('continue-btn');
const rememberCheckbox = document.getElementById('remember-checkbox');
const endIntentionBtn = document.getElementById('end-intention-btn');

// Check if phrase matches
phraseInput.addEventListener('input', () => {
  const matches = phraseInput.value === BREAK_GLASS_PHRASE;
  continueBtn.disabled = !matches;
});

// Handle continue
continueBtn.addEventListener('click', async () => {
  if (phraseInput.value !== BREAK_GLASS_PHRASE) return;

  continueBtn.disabled = true;
  continueBtn.textContent = 'Processing...';

  try {
    // Send override to native app
    const result = await new Promise((resolve) => {
      chrome.runtime.sendMessage({
        type: 'SUBMIT_OVERRIDE',
        url: blockedUrl,
        phrase: phraseInput.value,
        learn: rememberCheckbox.checked
      }, resolve);
    });

    if (result && result.success) {
      // The background script will navigate us
    } else {
      // Fallback: navigate directly
      window.location.href = blockedUrl;
    }
  } catch (error) {
    console.error('Override error:', error);
    // Fallback: navigate directly
    window.location.href = blockedUrl;
  }
});

// Handle end intention
endIntentionBtn.addEventListener('click', async () => {
  endIntentionBtn.disabled = true;
  endIntentionBtn.textContent = 'Ending intention...';

  try {
    // Send end intention request to native app
    await new Promise((resolve) => {
      chrome.runtime.sendMessage({
        type: 'END_INTENTION'
      }, resolve);
    });

    // Close this tab or navigate to new tab page
    window.location.href = 'chrome://newtab';
  } catch (error) {
    console.error('End intention error:', error);
    endIntentionBtn.disabled = false;
    endIntentionBtn.textContent = 'End intention and start a new one';
  }
});

// Focus the input on load
phraseInput.focus();

// Allow Enter to submit when phrase matches
phraseInput.addEventListener('keypress', (e) => {
  if (e.key === 'Enter' && !continueBtn.disabled) {
    continueBtn.click();
  }
});
