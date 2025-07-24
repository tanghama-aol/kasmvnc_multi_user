/**
 * KasmVNC多用户管理系统 - 通用JavaScript函数
 * 作者: Xander Xu
 */

// 全局变量
let loadingOverlay = null;

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    // 初始化工具提示
    initTooltips();
    
    // 设置当前导航项高亮
    setActiveNavItem();
    
    // 初始化所有模态框
    initModals();
});

/**
 * 显示Toast消息
 * @param {string} title - 标题
 * @param {string} message - 消息内容
 * @param {string} type - 类型: success, error, warning, info
 */
function showToast(title, message, type = 'info') {
    const toastContainer = document.getElementById('toastContainer');
    
    // 创建Toast元素
    const toastId = 'toast-' + Date.now();
    const toastHtml = `
        <div id="${toastId}" class="toast" role="alert" aria-live="assertive" aria-atomic="true">
            <div class="toast-header">
                <i class="bi ${getToastIcon(type)} me-2 text-${getToastColor(type)}"></i>
                <strong class="me-auto">${title}</strong>
                <small class="text-muted">刚刚</small>
                <button type="button" class="btn-close" data-bs-dismiss="toast" aria-label="Close"></button>
            </div>
            <div class="toast-body">
                ${message}
            </div>
        </div>
    `;
    
    // 添加到容器
    toastContainer.insertAdjacentHTML('beforeend', toastHtml);
    
    // 初始化并显示Toast
    const toastElement = document.getElementById(toastId);
    const toast = new bootstrap.Toast(toastElement, {
        autohide: true,
        delay: type === 'error' ? 8000 : 5000
    });
    
    toast.show();
    
    // Toast隐藏后移除元素
    toastElement.addEventListener('hidden.bs.toast', function() {
        toastElement.remove();
    });
}

/**
 * 获取Toast图标
 * @param {string} type - 类型
 * @returns {string} 图标类名
 */
function getToastIcon(type) {
    const icons = {
        success: 'bi-check-circle-fill',
        error: 'bi-x-circle-fill',
        warning: 'bi-exclamation-triangle-fill',
        info: 'bi-info-circle-fill'
    };
    return icons[type] || icons.info;
}

/**
 * 获取Toast颜色
 * @param {string} type - 类型
 * @returns {string} 颜色类名
 */
function getToastColor(type) {
    const colors = {
        success: 'success',
        error: 'danger',
        warning: 'warning',
        info: 'info'
    };
    return colors[type] || colors.info;
}

/**
 * 显示加载覆盖层
 * @param {string} message - 加载消息
 */
function showLoading(message = '处理中...') {
    if (loadingOverlay) {
        hideLoading();
    }
    
    const overlay = document.createElement('div');
    overlay.className = 'loading-overlay';
    overlay.innerHTML = `
        <div class="loading-content">
            <div class="spinner-border text-primary mb-3" role="status">
                <span class="visually-hidden">加载中...</span>
            </div>
            <div class="h5 mb-0">${message}</div>
        </div>
    `;
    
    document.body.appendChild(overlay);
    loadingOverlay = overlay;
    
    // 禁用滚动
    document.body.style.overflow = 'hidden';
}

/**
 * 隐藏加载覆盖层
 */
function hideLoading() {
    if (loadingOverlay) {
        document.body.removeChild(loadingOverlay);
        loadingOverlay = null;
        
        // 恢复滚动
        document.body.style.overflow = '';
    }
}

/**
 * 确认对话框
 * @param {string} message - 确认消息
 * @param {function} callback - 确认后的回调函数
 * @param {string} title - 对话框标题
 */
function showConfirm(message, callback, title = '确认操作') {
    if (confirm(`${title}\n\n${message}`)) {
        callback();
    }
}

/**
 * 格式化文件大小
 * @param {number} bytes - 字节数
 * @returns {string} 格式化后的大小
 */
function formatFileSize(bytes) {
    if (bytes === 0) return '0 B';
    
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

/**
 * 格式化时间戳
 * @param {number} timestamp - 时间戳（秒）
 * @returns {string} 格式化后的时间
 */
function formatTimestamp(timestamp) {
    const date = new Date(timestamp * 1000);
    return date.toLocaleString('zh-CN');
}

/**
 * 格式化持续时间
 * @param {number} seconds - 秒数
 * @returns {string} 格式化后的持续时间
 */
function formatDuration(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = Math.floor(seconds % 60);
    
    if (hours > 0) {
        return `${hours}:${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    } else {
        return `${minutes}:${secs.toString().padStart(2, '0')}`;
    }
}

/**
 * 复制文本到剪贴板
 * @param {string} text - 要复制的文本
 * @param {string} successMessage - 成功消息
 */
async function copyToClipboard(text, successMessage = '已复制到剪贴板') {
    try {
        await navigator.clipboard.writeText(text);
        showToast('成功', successMessage, 'success');
    } catch (err) {
        // 降级方案
        const textArea = document.createElement('textarea');
        textArea.value = text;
        document.body.appendChild(textArea);
        textArea.select();
        
        try {
            document.execCommand('copy');
            showToast('成功', successMessage, 'success');
        } catch (err) {
            showToast('错误', '复制失败', 'error');
        }
        
        document.body.removeChild(textArea);
    }
}

/**
 * 防抖函数
 * @param {function} func - 要防抖的函数
 * @param {number} wait - 等待时间（毫秒）
 * @returns {function} 防抖后的函数
 */
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

/**
 * 节流函数
 * @param {function} func - 要节流的函数
 * @param {number} limit - 限制时间（毫秒）
 * @returns {function} 节流后的函数
 */
function throttle(func, limit) {
    let inThrottle;
    return function(...args) {
        if (!inThrottle) {
            func.apply(this, args);
            inThrottle = true;
            setTimeout(() => inThrottle = false, limit);
        }
    };
}

/**
 * HTTP请求封装
 * @param {string} url - 请求URL
 * @param {object} options - 请求选项
 * @returns {Promise} 请求Promise
 */
async function apiRequest(url, options = {}) {
    const defaultOptions = {
        headers: {
            'Content-Type': 'application/json'
        }
    };
    
    const finalOptions = {
        ...defaultOptions,
        ...options,
        headers: {
            ...defaultOptions.headers,
            ...options.headers
        }
    };
    
    try {
        const response = await fetch(url, finalOptions);
        const result = await response.json();
        
        if (!response.ok) {
            throw new Error(result.message || `HTTP Error: ${response.status}`);
        }
        
        return result;
    } catch (error) {
        console.error('API请求失败:', error);
        throw error;
    }
}

/**
 * 获取服务状态样式类
 * @param {string} status - 服务状态
 * @returns {string} 样式类名
 */
function getStatusClass(status) {
    const statusClasses = {
        running: 'status-running',
        stopped: 'status-stopped',
        error: 'status-error',
        unknown: 'status-unknown'
    };
    return statusClasses[status] || statusClasses.unknown;
}

/**
 * 获取服务状态显示文本
 * @param {string} status - 服务状态
 * @returns {string} 显示文本
 */
function getStatusText(status) {
    const statusTexts = {
        running: '运行中',
        stopped: '已停止',
        error: '错误',
        unknown: '未知'
    };
    return statusTexts[status] || statusTexts.unknown;
}

/**
 * 初始化工具提示
 */
function initTooltips() {
    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    tooltipTriggerList.map(function(tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl);
    });
}

/**
 * 设置当前导航项高亮
 */
function setActiveNavItem() {
    const currentPath = window.location.pathname;
    const navLinks = document.querySelectorAll('.navbar-nav .nav-link');
    
    navLinks.forEach(link => {
        link.classList.remove('active');
        
        // 检查链接是否匹配当前路径
        if (link.getAttribute('href') === currentPath) {
            link.classList.add('active');
        }
    });
}

/**
 * 初始化模态框
 */
function initModals() {
    // 为所有模态框添加显示动画
    document.querySelectorAll('.modal').forEach(modal => {
        modal.addEventListener('shown.bs.modal', function() {
            const modalDialog = modal.querySelector('.modal-dialog');
            modalDialog.classList.add('fade-in');
        });
        
        modal.addEventListener('hidden.bs.modal', function() {
            const modalDialog = modal.querySelector('.modal-dialog');
            modalDialog.classList.remove('fade-in');
        });
    });
}

/**
 * 表格搜索功能
 * @param {string} searchInputId - 搜索输入框ID
 * @param {string} tableId - 表格ID
 */
function setupTableSearch(searchInputId, tableId) {
    const searchInput = document.getElementById(searchInputId);
    const table = document.getElementById(tableId);
    
    if (!searchInput || !table) return;
    
    const debouncedSearch = debounce(function(searchTerm) {
        const rows = table.querySelectorAll('tbody tr');
        
        rows.forEach(row => {
            const text = row.textContent.toLowerCase();
            const matches = text.includes(searchTerm.toLowerCase());
            row.style.display = matches ? '' : 'none';
        });
    }, 300);
    
    searchInput.addEventListener('input', function() {
        debouncedSearch(this.value);
    });
}

/**
 * 表格排序功能
 * @param {string} tableId - 表格ID
 */
function setupTableSort(tableId) {
    const table = document.getElementById(tableId);
    if (!table) return;
    
    const headers = table.querySelectorAll('th[data-sort]');
    
    headers.forEach(header => {
        header.style.cursor = 'pointer';
        header.innerHTML += ' <i class="bi bi-arrow-down-up ms-1"></i>';
        
        header.addEventListener('click', function() {
            const column = this.dataset.sort;
            const tbody = table.querySelector('tbody');
            const rows = Array.from(tbody.querySelectorAll('tr'));
            
            // 移除其他列的排序指示器
            headers.forEach(h => {
                if (h !== this) {
                    h.querySelector('i').className = 'bi bi-arrow-down-up ms-1';
                }
            });
            
            // 确定排序方向
            const icon = this.querySelector('i');
            const isAsc = icon.classList.contains('bi-arrow-down-up') || 
                         icon.classList.contains('bi-arrow-up');
            
            // 更新图标
            icon.className = isAsc ? 'bi bi-arrow-down ms-1' : 'bi bi-arrow-up ms-1';
            
            // 排序行
            rows.sort((a, b) => {
                const aValue = a.children[parseInt(column)].textContent.trim();
                const bValue = b.children[parseInt(column)].textContent.trim();
                
                // 尝试数字比较
                const aNum = parseFloat(aValue);
                const bNum = parseFloat(bValue);
                
                if (!isNaN(aNum) && !isNaN(bNum)) {
                    return isAsc ? aNum - bNum : bNum - aNum;
                } else {
                    return isAsc ? 
                        aValue.localeCompare(bValue) : 
                        bValue.localeCompare(aValue);
                }
            });
            
            // 重新插入排序后的行
            rows.forEach(row => tbody.appendChild(row));
        });
    });
}

/**
 * 自动刷新功能
 * @param {function} refreshFunction - 刷新函数
 * @param {number} interval - 刷新间隔（毫秒）
 * @returns {number} 定时器ID
 */
function setupAutoRefresh(refreshFunction, interval = 5000) {
    // 立即执行一次
    refreshFunction();
    
    // 设置定时刷新
    return setInterval(refreshFunction, interval);
}

/**
 * 页面可见性检测
 * @param {function} onVisible - 页面可见时的回调
 * @param {function} onHidden - 页面隐藏时的回调
 */
function setupVisibilityChange(onVisible, onHidden) {
    document.addEventListener('visibilitychange', function() {
        if (document.hidden) {
            if (onHidden) onHidden();
        } else {
            if (onVisible) onVisible();
        }
    });
}