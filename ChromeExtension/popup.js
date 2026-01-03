const contentDiv = document.getElementById('content');

async function updateStatus() {
  try {
    // Check if app is running
    const appRunning = await new Promise((resolve) => {
      chrome.runtime.sendMessage({ type: 'CHECK_APP_STATUS' }, resolve);
    });

    if (!appRunning) {
      showDisconnected();
      return;
    }

    // Get intention
    const intention = await new Promise((resolve) => {
      chrome.runtime.sendMessage({ type: 'GET_INTENTION' }, resolve);
    });

    if (intention && intention.active) {
      showIntention(intention);
    } else {
      showNoIntention();
    }
  } catch (error) {
    console.error('Error updating status:', error);
    showDisconnected();
  }
}

function showDisconnected() {
  contentDiv.innerHTML = `
    <div class="status disconnected">
      <div class="status-label">Status</div>
      <p class="error-message">Intention OS app not running</p>
      <p style="font-size: 12px; color: rgba(255,255,255,0.5); margin-top: 10px;">
        Make sure the Intention OS app is running on your Mac.
      </p>
    </div>
  `;
}

function showNoIntention() {
  contentDiv.innerHTML = `
    <div class="status">
      <div class="no-intention">
        <p>No active intention</p>
        <p style="font-size: 12px; margin-top: 8px;">
          Set an intention in the Intention OS app to start focusing.
        </p>
      </div>
    </div>
  `;
}

function showIntention(intention) {
  contentDiv.innerHTML = `
    <div class="status">
      <div class="status-label">Current Intention</div>
      <div class="intention-text">${escapeHtml(intention.text)}</div>
      <div class="timer">
        <div class="timer-item">
          <div class="timer-label">Remaining</div>
          <div class="timer-value">${intention.remaining || '∞'}</div>
        </div>
      </div>
    </div>
  `;
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// Update on load
updateStatus();

// Update periodically
setInterval(updateStatus, 5000);
