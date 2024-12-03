document.addEventListener('DOMContentLoaded', () => {
    const commandBlock = document.querySelector('.command-block');

    document.addEventListener('keydown', (e) => {
        if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'o')) {
            e.preventDefault();
        }
    });

    const copyToClipboard = async (text) => {
        try {
            if (!navigator.clipboard && !window.isSecureContext) {
                toast("Browser does not support clipboard API!", false);
                return;
            }

            navigator.clipboard.writeText(text)
                .catch(err => console.error('Failed to copy: ', err));

            toast("Copied to clipboard!");
        } catch (err) {
            console.error('Failed to copy:', err);
        }
    };

    commandBlock.addEventListener('click', () => {
        const code = commandBlock.querySelector('code').textContent;
        const cleanCode = code.replace(/^\$\s*/, '');
        copyToClipboard(cleanCode);
    });
});

function toast(message, success = true) {
    const toast = document.getElementById('toast');
    toast.querySelector('#toast span').textContent = message;
    toast.querySelector('#check-icon').style.display = success ? 'block' : 'none';
    toast.querySelector('#error-icon').style.display = success ? 'none' : 'block';
    toast.classList.add('show');
    setTimeout(() => {
        toast.classList.remove('show');
    }, 2000);
}