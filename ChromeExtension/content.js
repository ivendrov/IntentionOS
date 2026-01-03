// Intention OS Content Script
// This script runs on all pages to provide additional functionality

// Currently minimal - the background script handles most URL checking
// This could be expanded to:
// - Inject blocking overlays instead of redirecting
// - Monitor dynamic page navigation (SPAs)
// - Track time spent on pages

console.log('Intention OS content script loaded');

// Listen for messages from background script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'SHOW_OVERLAY') {
    // Could show an in-page overlay instead of redirecting
    // This would be less jarring for the user
  }

  if (message.type === 'GET_PAGE_INFO') {
    sendResponse({
      url: window.location.href,
      title: document.title
    });
  }
});
