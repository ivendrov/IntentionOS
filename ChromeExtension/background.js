// Intention OS Chrome Extension - Background Service Worker

const API_BASE = 'http://localhost:9999';

// Cache for URL check results
const urlCache = new Map();
const CACHE_TTL = 60000; // 1 minute cache

// Track blocked tabs to prevent redirect loops
const blockedTabs = new Set();

// Check if the native app is running
async function checkAppStatus() {
  try {
    const response = await fetch(`${API_BASE}/status`);
    if (response.ok) {
      const data = await response.json();
      return data.status === 'ok';
    }
  } catch (error) {
    console.log('Intention OS app not running');
  }
  return false;
}

// Get current intention
async function getIntention() {
  try {
    const response = await fetch(`${API_BASE}/intention`);
    if (response.ok) {
      return await response.json();
    }
  } catch (error) {
    console.log('Failed to get intention:', error);
  }
  return null;
}

// Check if URL is allowed
async function checkURL(url) {
  // Check cache first
  const cached = urlCache.get(url);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    return cached.result;
  }

  try {
    const response = await fetch(`${API_BASE}/check-url`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url })
    });

    if (response.ok) {
      const result = await response.json();
      urlCache.set(url, { result, timestamp: Date.now() });
      return result;
    }
  } catch (error) {
    console.log('Failed to check URL:', error);
  }

  // Default to allowed if we can't reach the app
  return { allowed: true, reason: 'app_unavailable' };
}

// Submit override phrase
async function submitOverride(url, phrase, learn) {
  try {
    const response = await fetch(`${API_BASE}/override`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url, phrase, learn })
    });

    if (response.ok) {
      const result = await response.json();
      // Clear cache for this URL
      urlCache.delete(url);
      return result;
    }
  } catch (error) {
    console.log('Failed to submit override:', error);
  }
  return { success: false };
}

// End intention
async function endIntention() {
  try {
    const response = await fetch(`${API_BASE}/end-intention`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    });

    if (response.ok) {
      // Clear URL cache
      urlCache.clear();
      return { success: true };
    }
  } catch (error) {
    console.log('Failed to end intention:', error);
  }
  return { success: false };
}

// Common function to check and block a URL
async function checkAndBlockURL(tabId, url) {
  // Skip chrome:// and extension pages
  if (url.startsWith('chrome://') ||
      url.startsWith('chrome-extension://') ||
      url.startsWith('about:')) {
    return;
  }

  // Skip our blocked page
  if (url.includes('blocked.html')) {
    return;
  }

  // Skip if this tab is already being blocked
  if (blockedTabs.has(tabId)) {
    return;
  }

  // Check if app is running
  const appRunning = await checkAppStatus();
  if (!appRunning) return;

  // Check intention
  const intention = await getIntention();
  if (!intention || !intention.active) return;

  // Check URL
  const result = await checkURL(url);

  if (!result.allowed) {
    // Mark tab as blocked
    blockedTabs.add(tabId);

    // Redirect to blocked page
    const blockedUrl = chrome.runtime.getURL('blocked.html') +
      `?url=${encodeURIComponent(url)}` +
      `&intention=${encodeURIComponent(intention.text)}`;

    chrome.tabs.update(tabId, { url: blockedUrl });

    // Clear blocked status after a short delay
    setTimeout(() => blockedTabs.delete(tabId), 2000);
  }
}

// Handle tab updates (URL changes within a tab)
chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  // Check when URL changes
  if (changeInfo.url) {
    await checkAndBlockURL(tabId, changeInfo.url);
  }
});

// Handle tab activation (switching to a tab)
chrome.tabs.onActivated.addListener(async (activeInfo) => {
  try {
    const tab = await chrome.tabs.get(activeInfo.tabId);
    if (tab.url) {
      await checkAndBlockURL(activeInfo.tabId, tab.url);
    }
  } catch (error) {
    // Tab might not exist anymore
  }
});

// Handle web navigation (catches more navigation events)
chrome.webNavigation.onCommitted.addListener(async (details) => {
  // Only check main frame navigations
  if (details.frameId !== 0) return;

  await checkAndBlockURL(details.tabId, details.url);
});

// Handle messages from content scripts and popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'CHECK_URL') {
    checkURL(message.url).then(sendResponse);
    return true;
  }

  if (message.type === 'GET_INTENTION') {
    getIntention().then(sendResponse);
    return true;
  }

  if (message.type === 'SUBMIT_OVERRIDE') {
    submitOverride(message.url, message.phrase, message.learn).then(result => {
      if (result.success) {
        // Navigate to the original URL
        chrome.tabs.update(sender.tab.id, { url: message.url });
      }
      sendResponse(result);
    });
    return true;
  }

  if (message.type === 'CHECK_APP_STATUS') {
    checkAppStatus().then(sendResponse);
    return true;
  }

  if (message.type === 'END_INTENTION') {
    endIntention().then(sendResponse);
    return true;
  }
});

// Clear cache when intention changes (poll every 30 seconds)
setInterval(async () => {
  const intention = await getIntention();
  // Could compare with cached intention and clear URL cache if changed
}, 30000);

console.log('Intention OS extension loaded');
