/* ============================================================
   AUST_trucker — html/js/admin.js
   Controle do Painel Administrativo de Rotas Dinâmicas & Spawns
   Padrão Visual Lation Modern UI (Emerald Edition)
   ============================================================ */

(function () {
  let adminData = {
    customRoutes: {},
    spawns: {},
    spawnFolders: ['Geral'],
    trailerOffsets: {},
    npcs: {},
    economy: {},
    homologatedProps: [],
    defaultProps: []
  };

  let activeTab = 'routes';
  let routeFilter = 'all';
  let routeSearchQuery = '';
  let ecoFilter = 'all';
  let draggedSpawnId = null;
  let selectedSpawnFolder = 'Geral';

  // ============================================================
  // COMPONENTES UI IN-GAME (MODAL E TOASTS 100% IN-GAME)
  // Elimina janelas nativas do Windows CEF fora do jogo
  // ============================================================

  function showConfirmModal(title, message, onConfirm) {
    const existing = document.getElementById('admin-confirm-modal');
    if (existing) existing.remove();

    const overlay = document.createElement('div');
    overlay.id = 'admin-confirm-modal';
    overlay.className = 'admin-modal-overlay';
    overlay.style.position = 'fixed';
    overlay.style.inset = '0';
    overlay.style.zIndex = '10000000';
    overlay.style.display = 'flex';
    overlay.style.alignItems = 'center';
    overlay.style.justifyContent = 'center';

    overlay.innerHTML = `
      <div class="admin-modal-box" style="z-index: 10000001; pointer-events: auto;">
        <div class="admin-modal-header">
          <i class="fas fa-exclamation-triangle"></i>
          <span>${escapeHtml(title || 'Confirmação')}</span>
        </div>
        <div class="admin-modal-body">
          ${escapeHtml(message || 'Tem certeza que deseja executar esta ação?')}
        </div>
        <div class="admin-modal-footer">
          <button class="admin-btn admin-btn-outline btn-modal-cancel">Cancelar</button>
          <button class="admin-btn admin-btn-danger btn-modal-confirm">Confirmar Exclusão</button>
        </div>
      </div>
    `;

    const closeFn = () => {
      window.removeEventListener('keydown', keyFn);
      overlay.remove();
    };

    const keyFn = (e) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        closeFn();
      }
    };

    overlay.querySelector('.btn-modal-cancel').addEventListener('click', closeFn);

    overlay.querySelector('.btn-modal-confirm').addEventListener('click', () => {
      closeFn();
      if (typeof onConfirm === 'function') onConfirm();
    });

    window.addEventListener('keydown', keyFn);
    document.body.appendChild(overlay);
  }

  function showPromptModal(title, placeholder, onConfirm) {
    const existing = document.getElementById('admin-prompt-modal');
    if (existing) existing.remove();

    const overlay = document.createElement('div');
    overlay.id = 'admin-prompt-modal';
    overlay.className = 'admin-modal-overlay';

    overlay.innerHTML = `
      <div class="admin-modal-box">
        <div class="admin-modal-header">
          <i class="fas fa-folder-plus" style="color:var(--admin-primary)"></i>
          <span>${escapeHtml(title || 'Nova Pasta')}</span>
        </div>
        <div class="admin-modal-body">
          <input type="text" id="modal-prompt-input" class="admin-input" placeholder="${escapeHtml(placeholder || '')}" style="width:100%; margin-top:4px;">
        </div>
        <div class="admin-modal-footer">
          <button class="admin-btn admin-btn-outline btn-modal-cancel">Cancelar</button>
          <button class="admin-btn admin-btn-primary btn-modal-submit">Criar</button>
        </div>
      </div>
    `;

    const input = overlay.querySelector('#modal-prompt-input');

    const submit = () => {
      const val = input.value.trim();
      overlay.remove();
      if (val && typeof onConfirm === 'function') onConfirm(val);
    };

    overlay.querySelector('.btn-modal-cancel').addEventListener('click', () => overlay.remove());
    overlay.querySelector('.btn-modal-submit').addEventListener('click', submit);
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') submit();
      if (e.key === 'Escape') overlay.remove();
    });

    const panel = document.getElementById('admin-panel') || document.body;
    panel.appendChild(overlay);
    setTimeout(() => input.focus(), 50);
  }

  function showAdminToast(message, type = 'success') {
    let container = document.getElementById('admin-toast-container');
    if (!container) {
      container = document.createElement('div');
      container.id = 'admin-toast-container';
      container.className = 'admin-toast-container';
      const panel = document.getElementById('admin-panel') || document.body;
      panel.appendChild(container);
    }

    const toast = document.createElement('div');
    toast.className = `admin-toast ${type === 'error' ? 'error' : ''}`;
    const icon = type === 'error' ? 'fa-exclamation-circle' : 'fa-check-circle';
    toast.innerHTML = `<i class="fas ${icon}"></i> <span>${escapeHtml(message)}</span>`;

    container.appendChild(toast);
    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transition = 'opacity 0.3s ease';
      setTimeout(() => toast.remove(), 300);
    }, 3500);
  }

  // ============================================================
  // COMUNICAÇÃO FIVEM NUI
  // ============================================================

  window.addEventListener('message', function (event) {
    const item = event.data;
    if (!item || !item.action) return;

    switch (item.action) {
      case 'admin_open':
        openAdminPanel(item.data);
        break;
      case 'admin_close':
        closeAdminPanel();
        break;
      case 'admin_minimize':
        minimizeAdminPanel();
        break;
      case 'admin_restore':
        restoreAdminPanel(item);
        break;
      case 'adminSyncRoutes':
        if (item.routes) {
          adminData.customRoutes = item.routes;
          renderRoutesTab();
          renderEconomyTab();
        }
        break;
      case 'adminSyncSpawns':
        if (item.spawns) {
          adminData.spawns = normalizeSpawns(item.spawns);
          renderSpawnsTab();
        }
        break;
      case 'adminSyncSpawnFolders':
        if (item.folders) {
          adminData.spawnFolders = normalizeFolders(item.folders);
          renderSpawnsTab();
          populateRouteSpawnFolders(document.getElementById('route-form-spawn-folder')?.value);
        }
        break;
      case 'admin_update_offsets':
        if (item.offsets) {
          adminData.trailerOffsets = item.offsets;
          renderOffsetsTab();
        }
        break;
      case 'admin_update_props':
        if (item.props) {
          adminData.homologatedProps = normalizeProps(item.props);
          renderPropsTab();
        }
        break;
      case 'admin_update_vehicle_prop_offsets':
        if (item.offsets) {
          adminData.vehiclePropOffsets = item.offsets;
          renderPropEditorTab();
        }
        break;
      case 'admin_propeditor_status':
        updatePropEditorStatus(item);
        break;
      case 'admin_propeditor_update_values':
        updatePropEditorValues(item.data);
        break;
      case 'admin_spawn_coords_calibrated':
        if (item.coords) {
          const sx = document.getElementById('spawn-form-x');
          const sy = document.getElementById('spawn-form-y');
          const sz = document.getElementById('spawn-form-z');
          const sh = document.getElementById('spawn-form-h');
          if (sx) sx.value = item.coords.x;
          if (sy) sy.value = item.coords.y;
          if (sz) sz.value = item.coords.z;
          if (sh) sh.value = item.coords.heading;
        }
        if (item.spawn && item.spawn.id) {
          if (!adminData.spawns || Array.isArray(adminData.spawns)) {
            adminData.spawns = normalizeSpawns(adminData.spawns);
          }
          adminData.spawns[item.spawn.id] = item.spawn;
          const sFolder = item.spawn.folder_name || item.spawn.folder || 'Geral';
          if (!adminData.spawnFolders) adminData.spawnFolders = ['Geral'];
          if (!adminData.spawnFolders.includes(sFolder)) {
            adminData.spawnFolders.push(sFolder);
          }
          selectedSpawnFolder = sFolder;
          renderSpawnsTab();
          populateRouteSpawnFolders(document.getElementById('route-form-spawn-folder')?.value);
          showAdminToast(`Ponto de Spawn "${item.spawn.name || item.spawn.id}" gravado e sincronizado!`, 'success');
        } else {
          showAdminToast('Coordenadas capturadas com sucesso!');
        }
        break;
      case 'admin_spawn_saved':
        if (item.spawn && item.spawn.id) {
          adminData.spawns[item.spawn.id] = item.spawn;
          renderSpawnsTab();
          showAdminToast(`Ponto "${item.spawn.name || item.spawn.id}" duplicado e salvo com sucesso!`, 'success');
        }
        break;
      case 'admin_npc_coords_calibrated':
        if (item.coords) {
          const nx = document.getElementById('npc-form-x');
          const ny = document.getElementById('npc-form-y');
          const nz = document.getElementById('npc-form-z');
          const nh = document.getElementById('npc-form-h');
          if (nx) nx.value = item.coords.x;
          if (ny) ny.value = item.coords.y;
          if (nz) nz.value = item.coords.z;
          if (nh) nh.value = item.coords.heading;
        }
        if (item.npc && item.npc.id) {
          if (!adminData.npcs) adminData.npcs = {};
          adminData.npcs[item.npc.id] = item.npc;
          renderNPCsTab();
          showAdminToast(`NPC Despachante "${item.npc.name || item.npc.id}" posicionado e salvo com sucesso!`, 'success');
        } else {
          showAdminToast('Coordenadas do NPC capturadas via Gizmo!', 'info');
        }
        break;
    }
  });

  // Fechar no ESC
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
      const confirmModal = document.getElementById('admin-confirm-modal');
      const promptModal = document.getElementById('admin-prompt-modal');
      if (confirmModal) { confirmModal.remove(); return; }
      if (promptModal) { promptModal.remove(); return; }

      const panel = document.getElementById('admin-panel');
      if (panel && panel.style.display === 'flex') {
        closeAdminPanel();
        postNUI('adminClose', {});
      }
    }
  });

  function postNUI(callbackName, data) {
    const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'AUST_trucker';
    return fetch(`https://${resourceName}/${callbackName}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {})
    }).then(res => res.json()).catch(() => ({}));
  }

  function normalizeSpawns(raw) {
    if (!raw) return {};
    const map = {};
    const processItem = (s, k) => {
      if (!s) return;
      const id = String(s.id || s.spawn_id || s.key || k || '').trim();
      if (!id) return;
      s.id = id;
      s.key = id;
      s.folder_name = String(s.folder_name || s.folderName || s.folder || s.spawn_folder || 'Geral').trim() || 'Geral';
      map[id] = s;
    };
    if (Array.isArray(raw)) {
      raw.forEach(processItem);
    } else if (typeof raw === 'object') {
      Object.keys(raw).forEach(k => processItem(raw[k], k));
    }
    return map;
  }

  function normalizeFolders(raw) {
    const list = new Set(['Geral']);
    const addItem = (f) => {
      if (!f) return;
      if (typeof f === 'string' && f.trim() !== '') list.add(f.trim());
      else if (typeof f === 'object' && f.name && typeof f.name === 'string' && f.name.trim() !== '') list.add(f.name.trim());
    };
    if (Array.isArray(raw)) {
      raw.forEach(addItem);
    } else if (raw && typeof raw === 'object') {
      Object.values(raw).forEach(addItem);
    }
    return Array.from(list);
  }

  function normalizeProps(raw) {
    if (!raw) return [];
    const list = Array.isArray(raw) ? raw : Object.values(raw);
    const seen = {};
    const res = [];
    list.forEach(p => {
      if (!p) return;
      const model = (p.prop_model || p.model_hash || p.model || '').toLowerCase().trim();
      if (!model || seen[model]) return;
      seen[model] = true;
      res.push({
        id: p.id,
        prop_model: model,
        modelHash: model,
        model: model,
        label: p.label || p.name || model,
        name: p.label || p.name || model,
        category: (p.category || p.cargo_category || 'dry').toLowerCase(),
        cargo_category: (p.category || p.cargo_category || 'dry').toLowerCase(),
        offset_z: parseFloat(p.offset_z != null ? p.offset_z : (p.offset ? p.offset.z : 0.0)) || 0.0,
        z: parseFloat(p.offset_z != null ? p.offset_z : (p.offset ? p.offset.z : 0.0)) || 0.0
      });
    });
    return res;
  }

  function openAdminPanel(data) {
    if (data) {
      adminData = {
        customRoutes: data.customRoutes || data.routes || {},
        spawns: normalizeSpawns(data.spawns),
        spawnFolders: normalizeFolders(data.spawnFolders || data.spawn_folders),
        trailerOffsets: data.trailerOffsets || data.offsets || {},
        vehiclePropOffsets: data.vehiclePropOffsets || {},
        npcs: data.npcs || {},
        economy: data.economy || {},
        homologatedProps: normalizeProps(data.homologatedProps || data.props || []),
        defaultProps: data.defaultProps || []
      };
    }
    const panel = document.getElementById('admin-panel');
    if (panel) {
      panel.style.display = 'flex';
      switchTab(activeTab);
    }
  }

  function closeAdminPanel() {
    const panel = document.getElementById('admin-panel');
    if (panel) {
      panel.style.display = 'none';
    }
  }

  function minimizeAdminPanel() {
    const panel = document.getElementById('admin-panel');
    if (panel) {
      panel.style.display = 'none';
    }
  }

  function restoreAdminPanel(item) {
    const panel = document.getElementById('admin-panel');
    if (panel) {
      panel.style.display = 'flex';
    }

    if (item && item.savedSlot && !item.isForklift) {
      const nextSlot = parseInt(item.savedSlot) + 1;
      const slotSelect = document.getElementById('offset-form-slot');
      if (slotSelect) {
        let exists = false;
        for (let i = 0; i < slotSelect.options.length; i++) {
          if (parseInt(slotSelect.options[i].value) === nextSlot) {
            slotSelect.selectedIndex = i;
            exists = true;
            break;
          }
        }
        if (!exists && nextSlot <= 12) {
          const opt = document.createElement('option');
          opt.value = nextSlot;
          opt.textContent = `Slot ${nextSlot} (Extra)`;
          slotSelect.appendChild(opt);
          slotSelect.value = nextSlot;
        }
      }
    }

    if (item && item.trailerModel) {
      const trailerInput = document.getElementById('offset-form-trailer');
      if (trailerInput) trailerInput.value = item.trailerModel;
    }

    const chkForklift = document.getElementById('offset-form-isforklift');
    const propInput = document.getElementById('offset-form-prop');
    const slotSelect = document.getElementById('offset-form-slot');
    if (item && item.isForklift) {
      if (chkForklift) chkForklift.checked = true;
      if (propInput) {
        propInput.value = 'forklift';
        propInput.disabled = true;
      }
      if (slotSelect) slotSelect.disabled = true;
    } else if (item && item.savedSlot) {
      if (chkForklift) chkForklift.checked = false;
      if (propInput) {
        propInput.value = 'hei_prop_carrier_cargo_04b';
        propInput.disabled = false;
      }
      if (slotSelect) slotSelect.disabled = false;
    }

    renderOffsetsTab();
    renderSpawnsTab();
  }

  function switchTab(tabName) {
    activeTab = tabName;
    document.querySelectorAll('.admin-tab-btn').forEach(btn => {
      btn.classList.toggle('active', btn.getAttribute('data-tab') === tabName);
    });
    document.querySelectorAll('.admin-tab-pane').forEach(pane => {
      pane.classList.toggle('active', pane.getAttribute('id') === `admin-tab-${tabName}`);
    });

    switch (tabName) {
      case 'routes':
        renderRoutesTab();
        break;
      case 'spawns':
        renderSpawnsTab();
        break;
      case 'props':
        renderPropsTab();
        break;
      case 'offsets':
        renderOffsetsTab();
        break;
      case 'propeditor':
        renderPropEditorTab();
        break;
      case 'economy':
        renderEconomyTab();
        break;
      case 'npcs':
        renderNPCsTab();
        break;
    }
  }

  // ============================================================
  // ABA 1: ROTAS & CONTRATOS (COM FILTROS E BUSCA)
  // ============================================================
  function getSpawnFolders() {
    const folders = new Set(['Geral']);
    if (adminData.spawnFolders && Array.isArray(adminData.spawnFolders)) {
      adminData.spawnFolders.forEach(f => { if (f) folders.add(f); });
    }
    const spawns = adminData.spawns || {};
    Object.values(spawns).forEach(s => {
      if (s && s.folder_name) folders.add(s.folder_name);
    });
    return Array.from(folders).sort();
  }

  function populateRouteSpawnFolders(selectedFolder) {
    const folderSelect = document.getElementById('route-form-spawn-folder');
    if (!folderSelect) return;
    const currentVal = selectedFolder || folderSelect.value;
    const folders = getSpawnFolders();
    folderSelect.innerHTML = '<option value="">Selecione a Pasta de Spawn...</option>';
    folders.forEach(fName => {
      const opt = document.createElement('option');
      opt.value = fName;
      opt.textContent = fName;
      folderSelect.appendChild(opt);
    });
    if (currentVal && folders.includes(currentVal)) {
      folderSelect.value = currentVal;
    }
  }

  function renderRoutesTab() {
    populateRouteSpawnFolders(document.getElementById('route-form-spawn-folder')?.value);
    const tbody = document.getElementById('admin-routes-tbody');
    if (!tbody) return;
    tbody.innerHTML = '';

    const routes = adminData.customRoutes || {};
    let entries = Object.keys(routes).map(k => ({ key: k, data: routes[k] }));

    if (routeFilter && routeFilter !== 'all') {
      entries = entries.filter(e => {
        const t = (e.data.type || e.data.job_type || 'freight').toLowerCase();
        return t === routeFilter;
      });
    }

    if (routeSearchQuery && routeSearchQuery.trim() !== '') {
      const q = routeSearchQuery.toLowerCase().trim();
      entries = entries.filter(e => {
        const name = (e.data.name || e.data.title || '').toLowerCase();
        const id = String(e.data.id || e.data.route_id || e.key).toLowerCase();
        return name.includes(q) || id.includes(q);
      });
    }

    if (entries.length === 0) {
      tbody.innerHTML = `<tr><td colspan="6" style="text-align:center; padding: 24px; color: var(--admin-text-muted);">Nenhuma rota encontrada para o filtro selecionado.</td></tr>`;
      return;
    }

    entries.forEach(e => {
      const r = e.data;
      const k = e.key;
      const tr = document.createElement('tr');
      const jobType = (r.type || r.job_type || 'freight').toLowerCase();
      let badgeClass = 'admin-badge-freight';
      if (jobType === 'adr') badgeClass = 'admin-badge-adr';
      else if (jobType === 'quick') badgeClass = 'admin-badge-quick';
      else if (jobType === 'heavy') badgeClass = 'admin-badge-heavy';
      else if (jobType === 'carrier') badgeClass = 'admin-badge-carrier';

      const payment = r.base_payment || r.payment || 0;
      const xp = r.base_xp || r.xp || 0;
      const dist = r.distance || r.distance_km || 0;

      tr.innerHTML = `
        <td style="font-weight:600; text-overflow:ellipsis; overflow:hidden;" title="#${escapeHtml(r.id || r.route_id || k)}">#${escapeHtml(r.id || r.route_id || k)}</td>
        <td style="overflow:hidden; text-overflow:ellipsis; white-space:nowrap;" title="${escapeHtml(r.name || r.title || 'Carga Sem Nome')}">${escapeHtml(r.name || r.title || 'Carga Sem Nome')}</td>
        <td style="text-align:center;"><span class="admin-badge ${badgeClass}">${escapeHtml(jobType.toUpperCase())}</span></td>
        <td>
          <div style="line-height:1.2;">
            <span>R$ ${Number(payment).toLocaleString()}</span><br>
            <span style="color:var(--admin-primary); font-size:10px; font-weight:600;">+${escapeHtml(xp)} XP</span>
          </div>
        </td>
        <td>
          <div style="line-height:1.2;">
            <span>${Number(dist).toFixed(1)} km</span><br>
            <span style="color:var(--admin-text-muted); font-size:10px;">Nv ${r.req_skill || r.required_level || 1}</span>
          </div>
        </td>
        <td style="text-align:center; white-space:nowrap;">
          <div style="display:inline-flex; gap:4px; justify-content:center; align-items:center;">
            <button class="admin-btn admin-btn-outline btn-edit-route" data-id="${escapeHtml(k)}" title="Editar Rota"><i class="fas fa-edit"></i></button>
            <button class="admin-btn admin-btn-danger btn-del-route" data-id="${escapeHtml(k)}" title="Excluir Rota"><i class="fas fa-trash"></i></button>
          </div>
        </td>
      `;
      tbody.appendChild(tr);
    });

    tbody.querySelectorAll('.btn-edit-route').forEach(btn => {
      btn.addEventListener('click', function () {
        const id = this.getAttribute('data-id');
        fillRouteForm(adminData.customRoutes[id]);
      });
    });

    tbody.querySelectorAll('.btn-del-route').forEach(btn => {
      btn.addEventListener('click', function () {
        const id = this.getAttribute('data-id');
        showConfirmModal('Excluir Rota', `Deseja realmente remover a rota #${id}?`, () => {
          postNUI('adminDeleteRoute', { id: id });
          delete adminData.customRoutes[id];
          const currId = document.getElementById('route-form-id')?.value.trim();
          if (currId === id) {
            clearRouteForm();
          }
          renderRoutesTab();
          renderEconomyTab();
          showAdminToast(`Rota #${id} excluída com sucesso.`);
        });
      });
    });
  }

  function clearRouteForm() {
    document.getElementById('route-form-id').value = '';
    document.getElementById('route-form-title').value = '';
    document.getElementById('route-form-type').value = 'freight';
    document.getElementById('route-form-prop').value = 'hei_prop_carrier_cargo_04b';
    document.getElementById('route-form-payment').value = 2500;
    document.getElementById('route-form-xp').value = 150;
    document.getElementById('route-form-distance').value = 5.0;
    document.getElementById('route-form-level').value = 1;
    populateRouteSpawnFolders('Geral');
    document.getElementById('route-form-pickup-x').value = '';
    document.getElementById('route-form-pickup-y').value = '';
    document.getElementById('route-form-pickup-z').value = '';
    document.getElementById('route-form-deliv-x').value = '';
    document.getElementById('route-form-deliv-y').value = '';
    document.getElementById('route-form-deliv-z').value = '';
    document.getElementById('route-form-forklift').checked = false;
    document.getElementById('route-form-adr').checked = false;

    const delBtn = document.getElementById('btn-delete-route');
    if (delBtn) delBtn.style.display = 'none';
  }

  function fillRouteForm(r) {
    if (!r) return;
    document.getElementById('route-form-id').value = r.id || r.route_id || '';
    document.getElementById('route-form-title').value = r.name || r.title || '';
    document.getElementById('route-form-type').value = r.type || r.job_type || 'freight';
    const propInput = document.getElementById('route-form-prop');
    if (propInput) propInput.value = r.cargo_model || r.cargo_prop || 'hei_prop_carrier_cargo_04b';
    document.getElementById('route-form-payment').value = r.base_payment || r.payment || 2500;
    document.getElementById('route-form-xp').value = r.base_xp || r.xp || 150;
    document.getElementById('route-form-distance').value = r.distance || r.distance_km || 5.0;
    document.getElementById('route-form-level').value = r.req_skill || r.required_level || 1;

    populateRouteSpawnFolders(r.spawn_folder || 'Geral');

    const dCoords = r.delivery_coords ? (typeof r.delivery_coords === 'string' ? JSON.parse(r.delivery_coords) : r.delivery_coords) : {};
    document.getElementById('route-form-deliv-x').value = dCoords.x ? Number(dCoords.x).toFixed(2) : '';
    document.getElementById('route-form-deliv-y').value = dCoords.y ? Number(dCoords.y).toFixed(2) : '';
    document.getElementById('route-form-deliv-z').value = dCoords.z ? Number(dCoords.z).toFixed(2) : '';

    document.getElementById('route-form-forklift').checked = (r.has_forklift == 1 || r.has_forklift === true);
    document.getElementById('route-form-adr').checked = (r.requires_adr == 1 || r.requires_adr === true || r.type === 'adr');

    const delBtn = document.getElementById('btn-delete-route');
    if (delBtn) delBtn.style.display = 'inline-flex';
  }

  function saveRouteForm() {
    const routeId = document.getElementById('route-form-id').value.trim();
    if (!routeId) {
      showAdminToast('Informe um identificador único para a rota (ex: rota_porto_oleo).', 'error');
      return;
    }

    const spawnFolder = (document.getElementById('route-form-spawn-folder')?.value || '').trim();
    if (!spawnFolder) {
      showAdminToast('Vínculo Obrigatório: Selecione uma Pasta de Spawn para esta rota!', 'error');
      return;
    }

    const spawnsInFolder = Object.values(adminData.spawns || {}).filter(s => (s.folder_name || 'Geral') === spawnFolder);
    if (spawnsInFolder.length === 0) {
      showAdminToast("A pasta selecionada está incompleta. Configure o Ponto de Coleta, Veículos e Props na aba 'Spawns Dinâmicos' antes de vinculá-la a esta rota.", 'error');
      return;
    }

    const delivery = {
      x: parseFloat(document.getElementById('route-form-deliv-x').value) || 0.0,
      y: parseFloat(document.getElementById('route-form-deliv-y').value) || 0.0,
      z: parseFloat(document.getElementById('route-form-deliv-z').value) || 0.0
    };

    const payload = {
      id: routeId,
      route_id: routeId,
      name: document.getElementById('route-form-title').value.trim() || 'Carga Personalizada',
      title: document.getElementById('route-form-title').value.trim() || 'Carga Personalizada',
      type: document.getElementById('route-form-type').value,
      job_type: document.getElementById('route-form-type').value,
      base_payment: parseInt(document.getElementById('route-form-payment').value) || 2500,
      payment: parseInt(document.getElementById('route-form-payment').value) || 2500,
      base_xp: parseInt(document.getElementById('route-form-xp').value) || 150,
      xp: parseInt(document.getElementById('route-form-xp').value) || 150,
      distance: parseFloat(document.getElementById('route-form-distance').value) || 5.0,
      distance_km: parseFloat(document.getElementById('route-form-distance').value) || 5.0,
      req_skill: parseInt(document.getElementById('route-form-level').value) || 1,
      required_level: parseInt(document.getElementById('route-form-level').value) || 1,
      spawn_folder: spawnFolder,
      delivery_coords: delivery,
      has_forklift: document.getElementById('route-form-forklift').checked ? 1 : 0,
      requires_adr: document.getElementById('route-form-adr').checked ? 1 : 0
    };

    postNUI('adminSaveRoute', payload);
    adminData.customRoutes[routeId] = payload;
    renderRoutesTab();
    renderEconomyTab();
    showAdminToast(`Rota #${routeId} salva e sincronizada em tempo real!`);
  }

  // ============================================================
  // ABA 2: SPAWNS DINÂMICOS (PASTAS & DRAG-AND-DROP)
  // ============================================================
  function fillSpawnForm(s) {
    if (!s) return;
    const coords = s.coords ? (typeof s.coords === 'string' ? JSON.parse(s.coords) : s.coords) : {};
    const hVal = coords.heading != null ? coords.heading : (coords.w != null ? coords.w : (s.heading != null ? s.heading : 0));
    const sId = document.getElementById('spawn-form-id');
    const sFolder = document.getElementById('spawn-form-folder');
    const sName = document.getElementById('spawn-form-name');
    const sType = document.getElementById('spawn-form-type');
    const sModel = document.getElementById('spawn-form-model');
    const sx = document.getElementById('spawn-form-x');
    const sy = document.getElementById('spawn-form-y');
    const sz = document.getElementById('spawn-form-z');
    const sh = document.getElementById('spawn-form-h');

    if (sId) sId.value = s.id || s.key || s.spawn_id || '';
    if (sFolder) {
      const f = s.folder_name || s.folderName || s.folder || 'Geral';
      sFolder.value = f;
      selectedSpawnFolder = f;
      document.querySelectorAll('.admin-folder-card').forEach(c => {
        c.style.borderColor = (c.getAttribute('data-folder') === f) ? 'var(--admin-primary)' : '';
      });
    }
    if (sName) sName.value = s.name || s.spawn_name || '';
    if (sType) {
      sType.value = s.spawn_type || 'truck';
      sType.dispatchEvent(new Event('change'));
    }
    if (sModel) sModel.value = s.model || '';
    if (sx && coords.x != null) sx.value = parseFloat(coords.x).toFixed(2);
    if (sy && coords.y != null) sy.value = parseFloat(coords.y).toFixed(2);
    if (sz && coords.z != null) sz.value = parseFloat(coords.z).toFixed(2);
    if (sh) sh.value = parseFloat(hVal).toFixed(1);
  }

  function populateSpawnModelSuggestions() {
    const datalist = document.getElementById('spawn-model-suggestions');
    if (!datalist) return;
    datalist.innerHTML = '';

    const suggestions = [
      { val: 'hauler', desc: 'Caminhão Hauler' },
      { val: 'packer', desc: 'Caminhão Packer' },
      { val: 'phantom', desc: 'Caminhão Phantom' },
      { val: 'trailers2', desc: 'Reboque Carga Geral' },
      { val: 'trailerlogs', desc: 'Reboque de Troncos' },
      { val: 'docktrailer', desc: 'Reboque Baixo Portuário' },
      { val: 'tanker', desc: 'Reboque Tanque Combustível' },
      { val: 'forklift', desc: 'Empilhadeira Padrão' },
      { val: 'handler', desc: 'Guindaste Dock Handler' },
      { val: 'hei_prop_carrier_cargo_04b', desc: 'Container Marítimo' }
    ];

    // Adiciona props homologados da aba de cargas
    const props = adminData.homologatedProps || [];
    props.forEach(p => {
      const model = p.prop_model || p.model_hash || p.name;
      if (model && !suggestions.some(s => s.val === model)) {
        suggestions.push({ val: model, desc: p.label || p.name || 'Prop Homologado' });
      }
    });

    suggestions.forEach(item => {
      const opt = document.createElement('option');
      opt.value = item.val;
      opt.label = item.desc;
      datalist.appendChild(opt);
    });
  }

  function getNextSequentialName(baseName, existingList) {
    if (!baseName) baseName = 'Ponto de Spawn';
    // Remove qualquer sufixo numérico existente, ex: "Vaga (2)" -> "Vaga"
    const cleanBase = baseName.replace(/\s*\(\d+\)$/, '').trim();
    let maxNum = 1;
    const escapedBase = cleanBase.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const regex = new RegExp(`^${escapedBase}(?:\\s*\\((\\d+)\\))?$`, 'i');

    (existingList || []).forEach(item => {
      const name = (item.name || item.spawn_name || item.custom_name || '').trim();
      const match = name.match(regex);
      if (match) {
        if (match[1]) {
          const num = parseInt(match[1], 10);
          if (num > maxNum) maxNum = num;
        } else {
          if (maxNum < 1) maxNum = 1;
        }
      }
    });

    return `${cleanBase} (${maxNum + 1})`;
  }

  function sanitizeSlug(name, existingMap) {
    if (!name) name = 'spawn';
    let slug = name
      .toLowerCase()
      .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '');
    if (!slug) slug = 'spawn';

    let uniqueId = slug;
    let counter = 2;
    while (existingMap && existingMap[uniqueId]) {
      uniqueId = `${slug}_${counter}`;
      counter++;
    }
    return uniqueId;
  }

  function getSpawnCategory(s) {
    const t = String(s.spawn_type || 'truck').toLowerCase().trim();
    if (t === 'pallet' || t === 'prop') return 'props';
    if (t === 'load_bay' || t === 'delivery_bay' || t === 'marker' || t === 'bay' || t === 'drawmarker') return 'bays';
    return 'vehicles'; // truck, trailer, forklift, handler, etc.
  }

  function renderSpawnsTab() {
    const container = document.getElementById('admin-spawns-folders-container');
    const folderSelect = document.getElementById('spawn-form-folder');
    if (!container) return;
    container.innerHTML = '';
    populateSpawnModelSuggestions();

    adminData.spawns = normalizeSpawns(adminData.spawns);
    const spawnsList = Object.values(adminData.spawns);

    const folderList = normalizeFolders(adminData.spawnFolders);
    const folders = {};
    folderList.forEach(f => {
      folders[f] = [];
    });

    spawnsList.forEach(s => {
      const fName = (s.folder_name && String(s.folder_name).trim()) || 'Geral';
      s.folder_name = fName;
      if (!folders[fName]) {
        folders[fName] = [];
        if (!folderList.includes(fName)) folderList.push(fName);
      }
      folders[fName].push(s);
    });

    if (folderSelect) {
      const currentSelected = selectedSpawnFolder || folderSelect.value;
      folderSelect.innerHTML = '';
      folderList.forEach(fName => {
        const opt = document.createElement('option');
        opt.value = fName;
        opt.textContent = fName;
        folderSelect.appendChild(opt);
      });
      if (currentSelected && folderList.includes(currentSelected)) {
        folderSelect.value = currentSelected;
        selectedSpawnFolder = currentSelected;
      } else {
        folderSelect.value = 'Geral';
        selectedSpawnFolder = 'Geral';
      }
      folderSelect.onchange = function () {
        selectedSpawnFolder = this.value;
        document.querySelectorAll('.admin-folder-card').forEach(c => {
          c.style.borderColor = (c.getAttribute('data-folder') === selectedSpawnFolder) ? 'var(--admin-primary)' : '';
        });
      };
    }

    window._openSpawnFolders = window._openSpawnFolders || new Set();
    window._activeSpawnFolderFilters = window._activeSpawnFolderFilters || {};

    folderList.forEach(folderName => {
      const fList = folders[folderName] || [];
      const isExpanded = window._openSpawnFolders.has(folderName);
      const activeFilter = window._activeSpawnFolderFilters[folderName] || 'all';

      let countVehicles = 0;
      let countProps = 0;
      let countBays = 0;
      fList.forEach(s => {
        const cat = getSpawnCategory(s);
        if (cat === 'vehicles') countVehicles++;
        else if (cat === 'props') countProps++;
        else if (cat === 'bays') countBays++;
      });

      const folderCard = document.createElement('div');
      folderCard.className = `admin-folder-card ${isExpanded ? 'expanded' : ''}`;
      folderCard.setAttribute('data-folder', folderName);
      if (folderName === selectedSpawnFolder) {
        folderCard.style.borderColor = 'var(--admin-primary)';
      }

      const isDefault = folderName === 'Geral';
      folderCard.innerHTML = `
        <div class="admin-folder-header">
          <div class="admin-folder-title">
            <i class="fas fa-folder${isExpanded ? '-open' : ''}"></i>
            <span>${escapeHtml(folderName)}</span>
            <span class="admin-folder-badge">${fList.length} ponto${fList.length !== 1 ? 's' : ''}</span>
          </div>
          <div style="display:flex; gap:10px; align-items:center;">
            ${!isDefault ? `<button class="admin-btn admin-btn-danger btn-del-folder" data-folder="${escapeHtml(folderName)}" style="padding: 2px 8px; font-size:10px;" title="Excluir Pasta"><i class="fas fa-trash"></i></button>` : ''}
            <i class="fas fa-chevron-right admin-folder-chevron"></i>
          </div>
        </div>
        <div class="admin-folder-body">
          <div class="admin-folder-filters">
            <button class="admin-filter-pill ${activeFilter === 'all' ? 'active' : ''}" data-filter="all">
              <i class="fas fa-list"></i> Todos (${fList.length})
            </button>
            <button class="admin-filter-pill ${activeFilter === 'vehicles' ? 'active' : ''}" data-filter="vehicles">
              <i class="fas fa-truck"></i> Veículos (${countVehicles})
            </button>
            <button class="admin-filter-pill ${activeFilter === 'props' ? 'active' : ''}" data-filter="props">
              <i class="fas fa-boxes-stacked"></i> Props (${countProps})
            </button>
            <button class="admin-filter-pill ${activeFilter === 'bays' ? 'active' : ''}" data-filter="bays">
              <i class="fas fa-warehouse"></i> Baias (${countBays})
            </button>
          </div>
          <div class="admin-folder-items" data-folder="${escapeHtml(folderName)}">
            ${fList.length === 0 ? `<div style="color:var(--admin-text-muted); font-size:11px; padding:10px; text-align:center;">Pasta vazia. Arraste pontos de spawn para cá.</div>` : ''}
          </div>
        </div>
      `;

      // Alternância do Acordeão (Expandir / Recolher)
      const header = folderCard.querySelector('.admin-folder-header');
      header.addEventListener('click', function (e) {
        if (e.target.closest('.btn-del-folder')) return;
        const currentlyOpen = folderCard.classList.contains('expanded');
        if (currentlyOpen) {
          folderCard.classList.remove('expanded');
          window._openSpawnFolders.delete(folderName);
          const icon = folderCard.querySelector('.admin-folder-title i');
          if (icon) icon.className = 'fas fa-folder';
        } else {
          folderCard.classList.add('expanded');
          window._openSpawnFolders.add(folderName);
          const icon = folderCard.querySelector('.admin-folder-title i');
          if (icon) icon.className = 'fas fa-folder-open';
        }

        // Seleção rápida da pasta no formulário
        selectedSpawnFolder = folderName;
        if (folderSelect) folderSelect.value = folderName;
        document.querySelectorAll('.admin-folder-card').forEach(c => {
          c.style.borderColor = (c.getAttribute('data-folder') === selectedSpawnFolder) ? 'var(--admin-primary)' : '';
        });
      });

      // Filtros Rápidos por Categoria (Pills)
      const filterPills = folderCard.querySelectorAll('.admin-filter-pill');
      const itemsContainer = folderCard.querySelector('.admin-folder-items');

      filterPills.forEach(pill => {
        pill.addEventListener('click', function (e) {
          e.stopPropagation();
          const filter = this.getAttribute('data-filter') || 'all';
          window._activeSpawnFolderFilters[folderName] = filter;
          filterPills.forEach(p => p.classList.remove('active'));
          this.classList.add('active');

          const rows = folderCard.querySelectorAll('.admin-spawn-row');
          let visibleCount = 0;
          rows.forEach(r => {
            const cat = r.getAttribute('data-category') || 'vehicles';
            if (filter === 'all' || cat === filter) {
              r.style.display = 'flex';
              visibleCount++;
            } else {
              r.style.display = 'none';
            }
          });

          let emptyFilterMsg = folderCard.querySelector('.admin-filter-empty-msg');
          if (visibleCount === 0 && fList.length > 0) {
            if (!emptyFilterMsg) {
              emptyFilterMsg = document.createElement('div');
              emptyFilterMsg.className = 'admin-filter-empty-msg';
              emptyFilterMsg.style.cssText = 'color:var(--admin-text-muted); font-size:11px; padding:12px; text-align:center;';
              itemsContainer.appendChild(emptyFilterMsg);
            }
            emptyFilterMsg.textContent = `Nenhum item do tipo "${filter === 'vehicles' ? 'Veículos' : (filter === 'props' ? 'Props' : 'Baias')}" nesta pasta.`;
            emptyFilterMsg.style.display = 'block';
          } else if (emptyFilterMsg) {
            emptyFilterMsg.style.display = 'none';
          }
        });
      });

      fList.forEach(s => {
        const cat = getSpawnCategory(s);
        const coords = s.coords ? (typeof s.coords === 'string' ? JSON.parse(s.coords) : s.coords) : {};
        const hVal = coords.heading != null ? coords.heading : (coords.w != null ? coords.w : (s.heading != null ? s.heading : 0));
        const row = document.createElement('div');
        row.className = 'admin-spawn-row';
        row.setAttribute('draggable', 'true');
        row.setAttribute('data-id', s.id || s.key || s.spawn_id);
        row.setAttribute('data-category', cat);
        if (activeFilter !== 'all' && cat !== activeFilter) {
          row.style.display = 'none';
        }

        row.innerHTML = `
          <div style="display:flex; align-items:center; gap:10px;">
            <i class="fas fa-grip-vertical" style="color:var(--admin-text-muted); cursor:grab;"></i>
            <strong>#${escapeHtml(s.id || s.key || s.spawn_id)}</strong>
            <span style="color:#fff;">${escapeHtml(s.name || s.spawn_name || 'Ponto')}</span>
            <span class="admin-badge admin-badge-quick">${escapeHtml((s.spawn_type || 'truck').toUpperCase())}</span>
            ${s.model ? `<span class="admin-badge admin-badge-primary" style="font-size:10px;"><i class="fas fa-box"></i> ${escapeHtml(s.model)}</span>` : ''}
          </div>
          <div style="font-family:monospace; font-size:11px; color:var(--admin-text-muted);">
            X:${coords.x ? Number(coords.x).toFixed(1) : 0} Y:${coords.y ? Number(coords.y).toFixed(1) : 0} Z:${coords.z ? Number(coords.z).toFixed(1) : 0} H:${Number(hVal).toFixed(0)}°
          </div>
          <div style="display:flex; gap:6px;">
            <button class="admin-btn admin-btn-outline btn-edit-spawn" data-id="${escapeHtml(s.id || s.key || s.spawn_id)}" style="padding: 3px 8px; font-size:11px;" title="Editar no Formulário"><i class="fas fa-edit"></i></button>
            <button class="admin-btn admin-btn-outline btn-dup-spawn" data-id="${escapeHtml(s.id || s.key || s.spawn_id)}" style="padding: 3px 8px; font-size:11px;" title="Duplicar (Gizmo 3D)"><i class="fas fa-copy"></i></button>
            <button class="admin-btn admin-btn-outline btn-tp-spawn" data-x="${escapeHtml(coords.x)}" data-y="${escapeHtml(coords.y)}" data-z="${escapeHtml(coords.z)}" data-h="${escapeHtml(hVal)}" style="padding: 3px 8px; font-size:11px;" title="Teleportar"><i class="fas fa-location-arrow"></i> TP</button>
            <button class="admin-btn admin-btn-danger btn-del-spawn" data-id="${escapeHtml(s.id || s.key || s.spawn_id)}" style="padding: 3px 8px; font-size:11px;" title="Excluir"><i class="fas fa-trash"></i></button>
          </div>
        `;

        row.addEventListener('dragstart', function (e) {
          draggedSpawnId = this.getAttribute('data-id');
          this.classList.add('dragging');
          e.dataTransfer.setData('text/plain', draggedSpawnId);
        });

        row.addEventListener('dragend', function () {
          this.classList.remove('dragging');
          draggedSpawnId = null;
        });

        itemsContainer.appendChild(row);
      });

      folderCard.addEventListener('dragover', function (e) {
        e.preventDefault();
        folderCard.classList.add('drag-over');
      });

      folderCard.addEventListener('dragleave', function () {
        folderCard.classList.remove('drag-over');
      });

      folderCard.addEventListener('drop', function (e) {
        e.preventDefault();
        folderCard.classList.remove('drag-over');
        const targetFolder = this.getAttribute('data-folder');
        if (draggedSpawnId && targetFolder) {
          const spawnObj = adminData.spawns[draggedSpawnId];
          if (spawnObj && spawnObj.folder_name !== targetFolder) {
            spawnObj.folder_name = targetFolder;
            postNUI('adminMoveSpawnFolder', {
              spawn_id: draggedSpawnId,
              folder_name: targetFolder
            });
            renderSpawnsTab();
            showAdminToast(`Spawn movido para "${targetFolder}".`);
          }
        }
      });

      container.appendChild(folderCard);
    });

    container.querySelectorAll('.btn-edit-spawn').forEach(btn => {
      btn.addEventListener('click', function () {
        const id = this.getAttribute('data-id');
        const s = adminData.spawns[id];
        if (s) {
          fillSpawnForm(s);
          showAdminToast(`Spawn #${id} carregado no formulário.`);
        }
      });
    });

    container.querySelectorAll('.btn-dup-spawn').forEach(btn => {
      btn.addEventListener('click', function () {
        const id = this.getAttribute('data-id');
        const s = adminData.spawns[id];
        if (!s) return;

        const spawnsList = Object.values(adminData.spawns || {});
        const baseName = s.name || s.spawn_name || s.id || 'Ponto de Spawn';
        const newName = getNextSequentialName(baseName, spawnsList);
        const newId = sanitizeSlug(newName, adminData.spawns);
        const coords = s.coords ? (typeof s.coords === 'string' ? JSON.parse(s.coords) : s.coords) : {};
        const hVal = coords.heading != null ? coords.heading : (coords.w != null ? coords.w : (s.heading != null ? s.heading : 0));

        const cloneObj = {
          id: newId,
          name: newName,
          spawn_type: s.spawn_type || 'truck',
          model: s.model || '',
          folder_name: s.folder_name || 'Geral',
          coords: {
            x: parseFloat(coords.x) || 0.0,
            y: parseFloat(coords.y) || 0.0,
            z: parseFloat(coords.z) || 0.0,
            heading: parseFloat(hVal) || 0.0,
            w: parseFloat(hVal) || 0.0
          }
        };

        // 1. Ativa Preview da Área com todos os spawns existentes
        if (spawnsList.length > 0) {
          postNUI('adminStartPreview', { spawns: spawnsList });
        }

        // 2. Aciona o Gizmo 3D posicionado nas coordenadas originais
        postNUI('adminStartSpawnGizmo', {
          spawn_type: cloneObj.spawn_type,
          model: cloneObj.model,
          coords: cloneObj.coords,
          is_duplication: true,
          duplicate_data: cloneObj
        });

        showAdminToast(`Duplicando "${baseName}" como "${newName}"... Ajuste a posição no Gizmo e aperte [ENTER]!`, 'info');
      });
    });

    container.querySelectorAll('.btn-tp-spawn').forEach(btn => {
      btn.addEventListener('click', function () {
        postNUI('adminTeleport', {
          coords: {
            x: parseFloat(this.getAttribute('data-x')),
            y: parseFloat(this.getAttribute('data-y')),
            z: parseFloat(this.getAttribute('data-z')),
            heading: parseFloat(this.getAttribute('data-h'))
          }
        });
      });
    });

    container.querySelectorAll('.btn-del-spawn').forEach(btn => {
      btn.addEventListener('click', function () {
        const id = this.getAttribute('data-id');
        showConfirmModal('Excluir Ponto de Spawn', `Deseja realmente excluir o spawn #${id}?`, () => {
          postNUI('adminDeleteSpawn', { id: id });
          delete adminData.spawns[id];
          renderSpawnsTab();
          showAdminToast(`Spawn #${id} excluído com sucesso.`);
        });
      });
    });

    container.querySelectorAll('.btn-del-folder').forEach(btn => {
      btn.addEventListener('click', function () {
        const f = this.getAttribute('data-folder');
        showConfirmModal('Excluir Pasta', `Deseja excluir a pasta "${f}"? Todos os pontos contidos nela serão movidos para "Geral".`, () => {
          postNUI('adminDeleteSpawnFolder', { folder_name: f });
          if (adminData.spawnFolders) {
            adminData.spawnFolders = adminData.spawnFolders.filter(x => x !== f);
          }
          Object.values(adminData.spawns).forEach(s => {
            if (s.folder_name === f) s.folder_name = 'Geral';
          });
          renderSpawnsTab();
          populateRouteSpawnFolders(document.getElementById('route-form-spawn-folder')?.value);
          showAdminToast(`Pasta "${f}" excluída. Pontos movidos para "Geral".`);
        });
      });
    });
  }

  function saveSpawnForm() {
    try {
      const spawnIdInput = document.getElementById('spawn-form-id');
      const spawnId = (spawnIdInput?.value || '').trim();
      if (!spawnId) {
        showAdminToast('Informe o ID do ponto de spawn!', 'error');
        if (spawnIdInput) spawnIdInput.focus();
        return;
      }

      const folderSelect = document.getElementById('spawn-form-folder');
      const folderVal = (selectedSpawnFolder || (folderSelect?.options && folderSelect.selectedIndex >= 0 ? folderSelect.options[folderSelect.selectedIndex]?.value : null) || folderSelect?.value || 'Geral').trim() || 'Geral';
      const sName = (document.getElementById('spawn-form-name')?.value || '').trim() || spawnId;
      const sType = document.getElementById('spawn-form-type')?.value || 'truck';
      const sModel = (document.getElementById('spawn-form-model')?.value || '').trim();

      const coords = {
        x: parseFloat(document.getElementById('spawn-form-x')?.value) || 0.0,
        y: parseFloat(document.getElementById('spawn-form-y')?.value) || 0.0,
        z: parseFloat(document.getElementById('spawn-form-z')?.value) || 0.0,
        heading: parseFloat(document.getElementById('spawn-form-h')?.value) || 0.0
      };

      const payload = {
        id: spawnId,
        spawn_id: spawnId,
        name: sName,
        spawn_name: sName,
        spawn_type: sType,
        model: sModel,
        folder_name: folderVal,
        folder: folderVal,
        folderName: folderVal,
        coords: coords,
        heading: coords.heading
      };

      // 1. Post para o servidor
      postNUI('adminSaveSpawn', payload);

      // 2. Atualiza cache local garantindo dicionário normalizado
      if (!adminData.spawns || Array.isArray(adminData.spawns)) {
        adminData.spawns = normalizeSpawns(adminData.spawns);
      }
      adminData.spawns[spawnId] = payload;

      if (!adminData.spawnFolders) adminData.spawnFolders = ['Geral'];
      if (!adminData.spawnFolders.includes(folderVal)) {
        adminData.spawnFolders.push(folderVal);
      }

      // 3. Renderiza a aba atualizada
      selectedSpawnFolder = folderVal;
      renderSpawnsTab();
      populateRouteSpawnFolders(document.getElementById('route-form-spawn-folder')?.value);

      // 4. Mantém a pasta ativa selecionada no formulário
      if (folderSelect) folderSelect.value = folderVal;

      // 5. Limpa campos para o próximo cadastro
      if (spawnIdInput) spawnIdInput.value = '';
      const nameInput = document.getElementById('spawn-form-name');
      if (nameInput) nameInput.value = '';
      const xInput = document.getElementById('spawn-form-x');
      if (xInput) xInput.value = '';
      const yInput = document.getElementById('spawn-form-y');
      if (yInput) yInput.value = '';
      const zInput = document.getElementById('spawn-form-z');
      if (zInput) zInput.value = '';
      const hInput = document.getElementById('spawn-form-h');
      if (hInput) hInput.value = '';
      const modelInput = document.getElementById('spawn-form-model');
      if (modelInput) modelInput.value = '';

      showAdminToast(`Ponto de spawn #${spawnId} gravado com sucesso na pasta "${folderVal}"!`, 'success');
    } catch (err) {
      console.error('[Admin NUI] Erro ao salvar spawn:', err);
      showAdminToast('Erro ao salvar ponto de spawn: ' + (err.message || err), 'error');
    }
  }

  // ============================================================
  // ABA 3: CARGAS & PROPS (HOMOLOGAÇÃO & VINCULAÇÃO)
  // ============================================================
  function renderPropsTab() {
    const grid = document.getElementById('admin-props-grid');
    if (!grid) return;
    grid.innerHTML = '';

    const list = normalizeProps(adminData.homologatedProps || []);

    const offsetDatalist = document.getElementById('offset-props-datalist');
    if (offsetDatalist) {
      offsetDatalist.innerHTML = list.map(p => `<option value="${escapeHtml(p.prop_model)}">${escapeHtml(p.name || p.prop_model)} (${escapeHtml(p.category || 'dry')})</option>`).join('');
    }

    if (list.length === 0) {
      grid.innerHTML = `
        <div style="grid-column: 1/-1; text-align: center; color: var(--admin-text-muted); padding: 40px; font-size: 13px;">
          <i class="fas fa-boxes" style="font-size: 28px; opacity: 0.3; margin-bottom: 8px; display: block;"></i>
          Nenhum prop de carga cadastrado no momento. Use o formulário acima para adicionar um novo modelo 3D.
        </div>
      `;
      return;
    }

    list.forEach(p => {
      const card = document.createElement('div');
      card.className = 'admin-card';
      card.style.display = 'flex';
      card.style.flexDirection = 'column';
      card.style.gap = '8px';

      const cat = (p.category || 'dry').toLowerCase();
      let badgeClass = 'admin-badge-freight';
      if (cat === 'adr') badgeClass = 'admin-badge-adr';
      else if (cat === 'fragile') badgeClass = 'admin-badge-quick';
      else if (cat === 'valuable') badgeClass = 'admin-badge-carrier';
      else if (cat === 'heavy') badgeClass = 'admin-badge-heavy';

      card.innerHTML = `
        <div class="admin-card-header" style="margin-bottom: 4px;">
          <strong style="color:var(--admin-primary); font-size:13px;"><i class="fas fa-cube"></i> ${escapeHtml(p.label || p.prop_model)}</strong>
          <span class="admin-badge ${badgeClass}">${escapeHtml(cat.toUpperCase())}</span>
        </div>
        <div style="font-size:11px; color:var(--admin-text-muted); font-family:monospace;">
          Modelo: <span style="color:#fff;">${escapeHtml(p.prop_model)}</span> | Offset Z: ${Number(p.offset_z || 0).toFixed(2)}
        </div>
        <div style="display:flex; justify-content:space-between; gap:8px; margin-top:8px;">
          <button class="admin-btn admin-btn-danger btn-del-prop" data-model="${escapeHtml(p.prop_model)}" style="padding: 4px 10px; font-size:11px;" title="Remover Homologação"><i class="fas fa-trash"></i></button>
          <button class="admin-btn admin-btn-outline btn-use-prop" data-prop="${escapeHtml(p.prop_model)}" style="padding: 4px 12px; font-size:11px;">Usar no Trailer</button>
        </div>
      `;
      grid.appendChild(card);
    });

    grid.querySelectorAll('.btn-use-prop').forEach(btn => {
      btn.addEventListener('click', function () {
        const prop = this.getAttribute('data-prop');
        document.getElementById('offset-form-prop').value = prop;
        switchTab('offsets');
      });
    });

    grid.querySelectorAll('.btn-del-prop').forEach(btn => {
      btn.addEventListener('click', function () {
        const model = this.getAttribute('data-model');
        showConfirmModal('Remover Homologação', `Deseja desomologar e remover o modelo "${model}"?`, () => {
          postNUI('adminDeleteHomologatedProp', { prop_model: model });
          adminData.homologatedProps = (adminData.homologatedProps || []).filter(p => {
            const m = (p.prop_model || p.model_hash || '').toLowerCase();
            return m !== model.toLowerCase();
          });
          renderPropsTab();
          showAdminToast(`Modelo "${model}" desvinculado com sucesso.`);
        });
      });
    });
  }

  function saveHomologatedProp() {
    const model = document.getElementById('prop-form-model').value.trim();
    if (!model) {
      showAdminToast('Informe o modelo 3D do prop (ex: prop_boxpile_07d).', 'error');
      return;
    }

    const labelVal = document.getElementById('prop-form-label').value.trim() || model;
    const catVal = document.getElementById('prop-form-category').value;
    const offsetZVal = parseFloat(document.getElementById('prop-form-offsetz').value) || 0.0;

    const payload = {
      prop_model: model,
      modelHash: model,
      model: model,
      label: labelVal,
      name: labelVal,
      category: catVal,
      cargo_category: catVal,
      offset_z: offsetZVal,
      z: offsetZVal
    };

    postNUI('adminSaveHomologatedProp', payload);

    adminData.homologatedProps = (adminData.homologatedProps || []).filter(p => {
      const m = (p.prop_model || p.model_hash || '').toLowerCase();
      return m !== model.toLowerCase();
    });
    adminData.homologatedProps.push(payload);
    renderPropsTab();
    showAdminToast(`Modelo "${model}" homologado com sucesso! Já disponível como carga.`);

    document.getElementById('prop-form-model').value = '';
    document.getElementById('prop-form-label').value = '';
    document.getElementById('prop-form-offsetz').value = '0.0';
  }

  // ============================================================
  // ABA 4: CALIBRAÇÃO VISUAL 3D DE OFFSETS (COM PASTAS, ACORDEÃO E PROPS DINÂMICOS)
  // ============================================================
  function getOffsetFolders() {
    const offsets = adminData.trailerOffsets || {};
    const folders = new Set(['Geral']);
    Object.values(offsets).forEach(item => {
      if (item && item.folder_name) folders.add(item.folder_name);
      if (item && item.pallets) {
        Object.values(item.pallets).forEach(p => {
          if (p && p.folder_name) folders.add(p.folder_name);
        });
      }
    });
    return Array.from(folders).sort();
  }

  function populateOffsetFolders(selectedFolder) {
    const folderSelect = document.getElementById('offset-form-folder');
    if (!folderSelect) return;
    const currentVal = selectedFolder || folderSelect.value;
    const folders = getOffsetFolders();
    folderSelect.innerHTML = '';
    folders.forEach(fName => {
      const opt = document.createElement('option');
      opt.value = fName;
      opt.textContent = fName;
      folderSelect.appendChild(opt);
    });
    if (currentVal && folders.includes(currentVal)) {
      folderSelect.value = currentVal;
    } else {
      folderSelect.value = 'Geral';
    }
  }

  function renderOffsetsTab() {
    populateOffsetFolders(document.getElementById('offset-form-folder')?.value);
    const listContainer = document.getElementById('admin-offsets-list');
    if (!listContainer) return;
    listContainer.innerHTML = '';

    const offsets = adminData.trailerOffsets || {};
    let allKeys = Object.keys(offsets);
    const textKeys = allKeys.filter(k => isNaN(Number(k)));

    const hasComposite = textKeys.some(k => k.includes('::'));
    let keys = textKeys;
    if (hasComposite) {
      keys = textKeys.filter(k => {
        if (k.includes('::')) return true;
        return !textKeys.some(other => other.startsWith(k + '::'));
      });
    }

    if (keys.length === 0) {
      listContainer.innerHTML = `<p style="color:var(--admin-text-muted); font-size:12px; padding: 12px;">Nenhum offset customizado salvo em banco ainda.</p>`;
      return;
    }

    keys.sort();

    // Agrupamento por Pastas / Categorias (Item 8)
    const folders = {};
    getOffsetFolders().forEach(f => { folders[f] = []; });
    if (!folders['Geral']) folders['Geral'] = [];

    keys.forEach(compKey => {
      const item = offsets[compKey];
      if (!item) return;
      const fName = item.folder_name || 'Geral';
      if (!folders[fName]) folders[fName] = [];
      folders[fName].push({ key: compKey, item: item });
    });

    window._openOffsetFolders = window._openOffsetFolders || new Set();

    Object.keys(folders).sort().forEach(folderName => {
      const fList = folders[folderName];
      const isExpanded = window._openOffsetFolders.has(folderName);

      const folderWrapper = document.createElement('div');
      folderWrapper.className = `admin-offsets-folder ${isExpanded ? 'expanded' : ''}`;
      folderWrapper.setAttribute('data-folder', folderName);

      folderWrapper.innerHTML = `
        <div class="admin-offsets-folder-header" data-folder="${escapeHtml(folderName)}">
          <div class="admin-offsets-folder-title">
            <i class="fas fa-folder${isExpanded ? '-open' : ''}" style="color:var(--admin-primary)"></i>
            <span>${escapeHtml(folderName)}</span>
            <span class="admin-folder-badge">${fList.length} config${fList.length !== 1 ? 's' : ''}</span>
          </div>
          <i class="fas fa-chevron-right admin-offsets-folder-chevron"></i>
        </div>
        <div class="admin-offsets-folder-content">
          ${fList.length === 0 ? `<div style="color:var(--admin-text-muted); font-size:11px; padding:10px; text-align:center;">Pasta vazia. Configure novos offsets nesta categoria.</div>` : ''}
        </div>
      `;

      const header = folderWrapper.querySelector('.admin-offsets-folder-header');
      header.addEventListener('click', () => {
        const currentlyOpen = folderWrapper.classList.contains('expanded');
        if (currentlyOpen) {
          folderWrapper.classList.remove('expanded');
          window._openOffsetFolders.delete(folderName);
          const icon = folderWrapper.querySelector('.admin-offsets-folder-title i');
          if (icon) icon.className = 'fas fa-folder';
        } else {
          folderWrapper.classList.add('expanded');
          window._openOffsetFolders.add(folderName);
          const icon = folderWrapper.querySelector('.admin-offsets-folder-title i');
          if (icon) icon.className = 'fas fa-folder-open';
        }
      });

      const contentBox = folderWrapper.querySelector('.admin-offsets-folder-content');

      fList.forEach(entry => {
        const compKey = entry.key;
        const item = entry.item;
        const trailerModel = (item.trailer_model || compKey.split('::')[0] || compKey).toLowerCase();
        const propModel = (item.prop_model || (compKey.includes('::') ? compKey.split('::')[1] : null) || 'hei_prop_carrier_cargo_04b');
        const customName = item.custom_name || null;
        const propCount = item.prop_count || 1;
        const groupLabel = item.label || null;

        let palletSlots = [];
        if (item.pallets) {
          const seen = new Set();
          Object.keys(item.pallets).forEach(k => {
            const num = parseInt(k);
            if (!isNaN(num) && !seen.has(num)) {
              seen.add(num);
              palletSlots.push({ slot: num, data: item.pallets[k] });
            }
          });
          palletSlots.sort((a, b) => a.slot - b.slot);
        }

        const card = document.createElement('div');
        card.className = 'admin-card';
        card.style.borderLeft = '4px solid var(--admin-primary)';
        card.style.marginBottom = '6px';
        card.innerHTML = `
          <div class="admin-card-header" style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:8px;">
            <div style="display:flex; align-items:center; flex-wrap:wrap; gap:6px;">
              ${customName ? `
                <span class="admin-badge admin-badge-adr" style="font-size: 11.5px; font-weight:700; padding: 3px 8px;" title="Nome Personalizado">
                  <i class="fas fa-tag"></i> ${escapeHtml(customName)}
                </span>
              ` : ''}
              <span class="admin-card-title"><i class="fas fa-truck"></i> <strong>${escapeHtml(trailerModel.toUpperCase())}</strong></span>
              <span class="admin-badge admin-badge-primary" style="font-size: 10.5px;">
                <i class="fas fa-box"></i> ${escapeHtml(propModel)}
              </span>
              <span class="admin-badge admin-badge-quick" style="font-size: 10px;" title="Quantidade de Props Exigidos">
                <i class="fas fa-boxes-stacked"></i> ${propCount} prop${propCount > 1 ? 's' : ''}
              </span>
              ${groupLabel ? `<span style="color:#94a3b8; font-size:11px;">(${escapeHtml(groupLabel)})</span>` : ''}
            </div>
            <div style="display:flex; gap:6px;">
              <button class="admin-btn admin-btn-outline btn-select-trailer" 
                data-model="${escapeHtml(trailerModel)}" 
                data-prop="${escapeHtml(propModel)}" 
                data-custom="${escapeHtml(customName || '')}" 
                data-count="${escapeHtml(propCount)}" 
                data-folder="${escapeHtml(folderName)}" 
                style="padding: 4px 10px; font-size: 11px;"><i class="fas fa-edit"></i> Configurar</button>
              <button class="admin-btn admin-btn-outline btn-duplicate-trailer-config" 
                data-model="${escapeHtml(trailerModel)}" 
                data-prop="${escapeHtml(propModel)}" 
                data-custom="${escapeHtml(customName || '')}" 
                data-count="${escapeHtml(propCount)}" 
                data-folder="${escapeHtml(folderName)}" 
                style="padding: 4px 8px; font-size: 11px;" title="Duplicar Configuração"><i class="fas fa-copy"></i> Duplicar</button>
              <button class="admin-btn admin-btn-danger btn-del-group" data-trailer="${escapeHtml(trailerModel)}" data-prop="${escapeHtml(propModel)}" style="padding: 4px 8px; font-size: 11px;" title="Excluir Todos os Slots"><i class="fas fa-trash"></i></button>
            </div>
          </div>
          <div style="font-size:12px; line-height: 1.6;">
            <div style="margin-bottom: 6px;"><strong>Slots de Paletes Calibrados:</strong></div>
            <div style="display:flex; flex-direction:column; gap:6px; margin-bottom: 8px;">
              ${palletSlots.length > 0 ? palletSlots.map(s => `
                <div style="display:flex; justify-content:space-between; align-items:center; background:rgba(255,255,255,0.03); padding:5px 10px; border-radius:6px; border: 1px solid rgba(255,255,255,0.05);">
                  <div style="display:flex; align-items:center; gap:8px; flex-wrap:wrap;">
                    <strong style="color:var(--admin-primary)">Slot ${s.slot}</strong> 
                    ${s.data.label ? `<span style="color:#f3f4f6; font-weight:600;">"${escapeHtml(s.data.label)}"</span>` : ''}
                    <span class="admin-badge admin-badge-primary" style="display:inline-flex; align-items:center; gap:4px; font-size:10px; padding:2px 8px; border-radius:4px;">
                      <i class="fas fa-box"></i> ${escapeHtml(s.data.prop_model || propModel)}
                    </span>
                    <span style="font-family:monospace; color:var(--admin-text-muted); font-size:11px;">[X:${Number(s.data.x).toFixed(2)}, Y:${Number(s.data.y).toFixed(2)}, Z:${Number(s.data.z).toFixed(2)}, H:${Number(s.data.heading || 0).toFixed(0)}°]</span>
                  </div>
                  <div style="display:flex; gap:4px; align-items:center;">
                    <button class="admin-btn admin-btn-outline btn-dup-slot" data-trailer="${escapeHtml(trailerModel)}" data-prop="${escapeHtml(s.data.prop_model || propModel)}" data-slot="${escapeHtml(s.slot)}" data-custom="${escapeHtml(customName || '')}" data-folder="${escapeHtml(folderName)}" data-count="${escapeHtml(propCount)}" style="padding:3px 8px; font-size:10px;" title="Duplicar para Próximo Slot (Gizmo 3D)"><i class="fas fa-copy"></i></button>
                    <button class="admin-btn admin-btn-danger btn-del-offset" data-id="${escapeHtml(s.data && s.data.id ? s.data.id : '')}" data-trailer="${escapeHtml(trailerModel)}" data-prop="${escapeHtml(s.data.prop_model || propModel)}" data-slot="${escapeHtml(s.slot)}" data-fork="0" style="padding:3px 8px; font-size:10px;" title="Excluir Offset"><i class="fas fa-trash"></i></button>
                  </div>
                </div>
              `).join('') : '<span style="color:var(--admin-text-muted)">Nenhum slot cadastrado</span>'}
            </div>
            <div>
              <strong>Empilhadeira Traseira:</strong> 
              ${item.forklift ? `
                <div style="display:inline-flex; align-items:center; gap:8px; background:rgba(255,255,255,0.03); padding:4px 10px; border-radius:6px; border: 1px solid rgba(255,255,255,0.05); margin-left:8px;">
                  ${item.forklift.label ? `<span style="color:#f3f4f6; font-weight:600;">"${escapeHtml(item.forklift.label)}"</span>` : ''}
                  <span class="admin-badge admin-badge-primary" style="display:inline-flex; align-items:center; gap:4px; font-size:10px; padding:2px 8px; border-radius:4px;"><i class="fas fa-truck-ramp-box"></i> ${escapeHtml(item.forklift.prop_model || 'forklift')}</span>
                  <span style="font-family:monospace; color:var(--admin-text-muted); font-size:11px;">[X:${Number(item.forklift.x).toFixed(2)}, Y:${Number(item.forklift.y).toFixed(2)}, Z:${Number(item.forklift.z).toFixed(2)}]</span>
                  <button class="admin-btn admin-btn-danger btn-del-offset" data-id="${escapeHtml(item.forklift && item.forklift.id ? item.forklift.id : '')}" data-trailer="${escapeHtml(trailerModel)}" data-prop="forklift" data-slot="7" data-fork="1" style="padding:3px 8px; font-size:10px;" title="Excluir Forklift"><i class="fas fa-trash"></i></button>
                </div>
              ` : '<span style="color:var(--admin-text-muted)">Padrão de Fábrica</span>'}
            </div>
          </div>
        `;
        contentBox.appendChild(card);
      });

      listContainer.appendChild(folderWrapper);
    });

    listContainer.querySelectorAll('.btn-select-trailer').forEach(btn => {
      btn.addEventListener('click', function () {
        const m = this.getAttribute('data-model');
        const p = this.getAttribute('data-prop');
        const c = this.getAttribute('data-custom') || '';
        const count = this.getAttribute('data-count') || '1';
        const folder = this.getAttribute('data-folder') || 'Geral';

        const trailerInput = document.getElementById('offset-form-trailer');
        const propInput = document.getElementById('offset-form-prop');
        const customInput = document.getElementById('offset-form-custom-name');
        const countInput = document.getElementById('offset-form-prop-count');
        const folderSelect = document.getElementById('offset-form-folder');

        if (trailerInput) trailerInput.value = m;
        if (propInput && p) propInput.value = p;
        if (customInput) customInput.value = c;
        if (countInput) countInput.value = count;
        if (folderSelect) {
          populateOffsetFolders(folder);
          folderSelect.value = folder;
        }
        if (trailerInput) trailerInput.focus();
      });
    });

    listContainer.querySelectorAll('.btn-duplicate-trailer-config').forEach(btn => {
      btn.addEventListener('click', function () {
        const m = this.getAttribute('data-model');
        const p = this.getAttribute('data-prop');
        const c = this.getAttribute('data-custom') || m;
        const count = this.getAttribute('data-count') || '1';
        const folder = this.getAttribute('data-folder') || 'Geral';

        const allOffsets = Object.values(adminData.trailerOffsets || {});
        const newCustomName = getNextSequentialName(c, allOffsets);

        const trailerInput = document.getElementById('offset-form-trailer');
        const propInput = document.getElementById('offset-form-prop');
        const customInput = document.getElementById('offset-form-custom-name');
        const countInput = document.getElementById('offset-form-prop-count');
        const folderSelect = document.getElementById('offset-form-folder');
        const slotInput = document.getElementById('offset-form-slot');

        if (trailerInput) trailerInput.value = m;
        if (propInput && p) propInput.value = p;
        if (customInput) customInput.value = newCustomName;
        if (countInput) countInput.value = count;
        if (folderSelect) {
          populateOffsetFolders(folder);
          folderSelect.value = folder;
        }
        if (slotInput) slotInput.value = '1';

        showAdminToast(`Clonando para "${newCustomName}". Ajuste o primeiro slot com o Gizmo 3D!`, 'info');
      });
    });

    listContainer.querySelectorAll('.btn-dup-slot').forEach(btn => {
      btn.addEventListener('click', function () {
        const trailer = this.getAttribute('data-trailer');
        const prop = this.getAttribute('data-prop');
        const slot = parseInt(this.getAttribute('data-slot')) || 1;
        const nextSlot = slot + 1;
        const custom = this.getAttribute('data-custom') || '';
        const folder = this.getAttribute('data-folder') || 'Geral';
        const count = this.getAttribute('data-count') || '1';

        const trailerInput = document.getElementById('offset-form-trailer');
        const propInput = document.getElementById('offset-form-prop');
        const slotInput = document.getElementById('offset-form-slot');
        const customInput = document.getElementById('offset-form-custom-name');
        const folderSelect = document.getElementById('offset-form-folder');
        const countInput = document.getElementById('offset-form-prop-count');

        if (trailerInput) trailerInput.value = trailer;
        if (propInput) propInput.value = prop;
        if (slotInput) slotInput.value = String(nextSlot);
        if (customInput) customInput.value = custom;
        if (folderSelect) {
          populateOffsetFolders(folder);
          folderSelect.value = folder;
        }
        if (countInput) countInput.value = count;

        showAdminToast(`Slot ${slot} duplicado para o Slot ${nextSlot}. Abrindo Gizmo 3D...`, 'info');
        startCalibrationTool();
      });
    });

    listContainer.querySelectorAll('.btn-del-group').forEach(btn => {
      btn.addEventListener('click', function () {
        const trailer = this.getAttribute('data-trailer');
        const prop = this.getAttribute('data-prop');
        showConfirmModal(
          'Excluir Configuração Completa',
          `Deseja realmente remover TODOS os slots do trailer "${trailer.toUpperCase()}" com a carga "${prop}"?`,
          () => {
            postNUI('adminDeleteTrailerOffset', {
              trailerModel: trailer,
              propModel: prop
            });
            const compKey = trailer.toLowerCase() + '::' + prop.toLowerCase();
            delete adminData.trailerOffsets[compKey];
            delete adminData.trailerOffsets[trailer.toLowerCase()];
            renderOffsetsTab();
            showAdminToast(`Configuração de ${trailer} (${prop}) excluída com sucesso.`);
          }
        );
      });
    });

    listContainer.querySelectorAll('.btn-del-offset').forEach(btn => {
      btn.addEventListener('click', function () {
        const trailer = this.getAttribute('data-trailer');
        const prop = this.getAttribute('data-prop');
        const slot = parseInt(this.getAttribute('data-slot'));
        const isFork = this.getAttribute('data-fork') === '1';
        const offsetId = parseInt(this.getAttribute('data-id')) || null;
        const targetDesc = isFork ? 'Empilhadeira Traseira' : `Slot ${slot}`;

        showConfirmModal(
          'Excluir Offset',
          `Deseja realmente remover o offset do trailer "${trailer}" [${prop}] (${targetDesc})?`,
          () => {
            postNUI('adminDeleteTrailerOffset', {
              id: offsetId,
              trailerModel: trailer,
              propModel: prop,
              slotIndex: slot,
              isForklift: isFork
            });
            const compKey = trailer.toLowerCase() + '::' + prop.toLowerCase();
            [compKey, trailer.toLowerCase()].forEach(k => {
              const trData = adminData.trailerOffsets[k];
              if (trData) {
                if (isFork) {
                  trData.forklift = null;
                } else if (trData.pallets) {
                  delete trData.pallets[slot];
                  delete trData.pallets[String(slot)];
                  if (offsetId) {
                    Object.keys(trData.pallets).forEach(pk => {
                      if (trData.pallets[pk] && trData.pallets[pk].id === offsetId) {
                        delete trData.pallets[pk];
                      }
                    });
                  }
                }
              }
            });
            renderOffsetsTab();
            showAdminToast(`Offset do trailer ${trailer} [${prop}] removido com sucesso.`);
          }
        );
      });
    });
  }

  function startCalibrationTool() {
    const trailerModel = document.getElementById('offset-form-trailer').value.trim() || 'trailers2';
    const isForklift = document.getElementById('offset-form-isforklift').checked;
    const slotIndex = isForklift ? 7 : (parseInt(document.getElementById('offset-form-slot').value) || 1);
    const propModel = isForklift ? 'forklift' : (document.getElementById('offset-form-prop').value.trim() || 'hei_prop_carrier_cargo_04b');
    const label = document.getElementById('offset-form-label').value.trim();
    const customName = (document.getElementById('offset-form-custom-name')?.value || '').trim();
    const propCount = parseInt(document.getElementById('offset-form-prop-count')?.value) || 1;
    const folderName = (document.getElementById('offset-form-folder')?.value || 'Geral').trim() || 'Geral';

    postNUI('adminStartOffsetCalibration', {
      trailerModel: trailerModel,
      slotIndex: slotIndex,
      isForklift: isForklift,
      propModel: propModel,
      label: label,
      customName: customName,
      propCount: propCount,
      folderName: folderName
    });
  }

  // ============================================================
  // ABA 5: ECONOMIA & XP (LISTAGEM GLOBAL & EDIÇÃO INLINE)
  // ============================================================
  function renderEconomyTab() {
    const tbody = document.getElementById('admin-eco-routes-tbody');
    if (tbody) {
      tbody.innerHTML = '';
      const routes = adminData.customRoutes || {};
      let entries = Object.keys(routes).map(k => ({ key: k, data: routes[k] }));

      if (ecoFilter && ecoFilter !== 'all') {
        entries = entries.filter(e => {
          const t = (e.data.type || e.data.job_type || 'freight').toLowerCase();
          return t === ecoFilter;
        });
      }

      if (entries.length === 0) {
        tbody.innerHTML = `<tr><td colspan="7" style="text-align:center; padding: 18px; color: var(--admin-text-muted);">Nenhuma rota encontrada para este tipo.</td></tr>`;
      } else {
        entries.forEach(e => {
          const r = e.data;
          const k = e.key;
          const tr = document.createElement('tr');
          const jobType = (r.type || r.job_type || 'freight').toLowerCase();
          let badgeClass = 'admin-badge-freight';
          if (jobType === 'adr') badgeClass = 'admin-badge-adr';
          else if (jobType === 'quick') badgeClass = 'admin-badge-quick';
          else if (jobType === 'heavy') badgeClass = 'admin-badge-heavy';
          else if (jobType === 'carrier') badgeClass = 'admin-badge-carrier';

          const payment = r.base_payment || r.payment || 2500;
          const xp = r.base_xp || r.xp || 150;
          const dist = r.distance || r.distance_km || 5.0;

          tr.innerHTML = `
            <td style="font-weight:600;">#${escapeHtml(r.id || r.route_id || k)}</td>
            <td title="${escapeHtml(r.name || r.title || 'Carga')}">${escapeHtml(r.name || r.title || 'Carga')}</td>
            <td style="text-align:center;"><span class="admin-badge ${badgeClass}">${escapeHtml(jobType.toUpperCase())}</span></td>
            <td>${Number(dist).toFixed(1)} km</td>
            <td>
              <input type="number" class="admin-inline-input eco-route-pay" data-id="${escapeHtml(k)}" value="${escapeHtml(payment)}">
            </td>
            <td>
              <input type="number" class="admin-inline-input eco-route-xp" data-id="${escapeHtml(k)}" value="${escapeHtml(xp)}">
            </td>
            <td style="text-align:center;">
              <button class="admin-btn admin-btn-primary btn-save-route-eco" data-id="${escapeHtml(k)}" style="padding: 4px 8px; font-size:11px;" title="Salvar"><i class="fas fa-save"></i></button>
            </td>
          `;
          tbody.appendChild(tr);
        });

        tbody.querySelectorAll('.btn-save-route-eco').forEach(btn => {
          btn.addEventListener('click', function () {
            const id = this.getAttribute('data-id');
            const row = this.closest('tr');
            const newPay = parseInt(row.querySelector('.eco-route-pay').value) || 2500;
            const newXp = parseInt(row.querySelector('.eco-route-xp').value) || 150;

            if (adminData.customRoutes[id]) {
              adminData.customRoutes[id].base_payment = newPay;
              adminData.customRoutes[id].payment = newPay;
              adminData.customRoutes[id].base_xp = newXp;
              adminData.customRoutes[id].xp = newXp;

              postNUI('adminSaveRoute', adminData.customRoutes[id]);
              showAdminToast(`Valores da rota #${id} atualizados para R$ ${newPay.toLocaleString()} e ${newXp} XP!`);
            }
          });
        });
      }
    }

    const eco = adminData.economy || {};
    if (document.getElementById('eco-form-km-pay')) {
      document.getElementById('eco-form-km-pay').value = eco.base_payment_per_km || 18.5;
      document.getElementById('eco-form-km-xp').value = eco.base_xp_per_km || 5.0;
      document.getElementById('eco-form-adr-mult').value = eco.adr_multiplier || 1.45;
      document.getElementById('eco-form-fragile-mult').value = eco.fragile_bonus || 1.25;
      document.getElementById('eco-form-valuable-mult').value = eco.valuable_bonus || 1.35;
      document.getElementById('eco-form-penalty').value = eco.cargo_loss_penalty || 500;
    }
  }

  function saveEconomyForm() {
    const payload = {
      base_payment_per_km: parseFloat(document.getElementById('eco-form-km-pay').value) || 18.5,
      base_xp_per_km: parseFloat(document.getElementById('eco-form-km-xp').value) || 5.0,
      adr_multiplier: parseFloat(document.getElementById('eco-form-adr-mult').value) || 1.45,
      fragile_bonus: parseFloat(document.getElementById('eco-form-fragile-mult').value) || 1.25,
      valuable_bonus: parseFloat(document.getElementById('eco-form-valuable-mult').value) || 1.35,
      cargo_loss_penalty: parseFloat(document.getElementById('eco-form-penalty').value) || 500
    };

    postNUI('adminSaveEconomy', payload);
    adminData.economy = payload;
    showAdminToast('Multiplicadores globais atualizados e sincronizados!');
  }

  // ============================================================
  // ABA 6: NPCS DESPACHANTES DINÂMICOS
  // ============================================================
  function renderNPCsTab() {
    const tbody = document.getElementById('admin-npcs-tbody');
    if (!tbody) return;
    tbody.innerHTML = '';

    const npcs = adminData.npcs || {};
    const keys = Object.keys(npcs);

    if (keys.length === 0) {
      tbody.innerHTML = `<tr><td colspan="5" style="text-align:center; padding: 24px; color: var(--admin-text-muted);">Nenhum NPC despachante adicionado. Crie um abaixo!</td></tr>`;
      return;
    }

    keys.forEach(k => {
      const n = npcs[k];
      const coords = n.coords ? (typeof n.coords === 'string' ? JSON.parse(n.coords) : n.coords) : {};
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td style="font-weight:600;">#${escapeHtml(n.npc_id || k)}</td>
        <td title="${escapeHtml(n.npc_name || 'Despachante')}">${escapeHtml(n.npc_name || 'Despachante')}</td>
        <td style="text-align:center;"><span class="admin-badge admin-badge-heavy">${escapeHtml(n.npc_model || 's_m_m_trucker_01')}</span></td>
        <td style="font-family: monospace; font-size: 10.5px;">
          X:${coords.x ? Number(coords.x).toFixed(1) : 0} Y:${coords.y ? Number(coords.y).toFixed(1) : 0} Z:${coords.z ? Number(coords.z).toFixed(1) : 0}
        </td>
        <td style="text-align:center; white-space: nowrap;">
          <div style="display:inline-flex; gap:4px; justify-content:center; align-items:center;">
            <button class="admin-btn admin-btn-accent btn-gizmo-npc-row" data-id="${escapeHtml(k)}" data-name="${escapeHtml(n.npc_name || n.name || '')}" data-model="${escapeHtml(n.npc_model || n.model || '')}" data-x="${escapeHtml(coords.x || '')}" data-y="${escapeHtml(coords.y || '')}" data-z="${escapeHtml(coords.z || '')}" data-h="${escapeHtml(coords.heading || coords.w || '')}" title="Ajustar Posição com Gizmo 3D"><i class="fas fa-arrows-alt"></i></button>
            <button class="admin-btn admin-btn-outline btn-tp-npc" data-x="${escapeHtml(coords.x)}" data-y="${escapeHtml(coords.y)}" data-z="${escapeHtml(coords.z)}" data-h="${escapeHtml(coords.heading)}" title="Teleportar"><i class="fas fa-location-arrow"></i></button>
            <button class="admin-btn admin-btn-danger btn-del-npc" data-id="${escapeHtml(k)}" title="Remover"><i class="fas fa-trash"></i></button>
          </div>
        </td>
      `;
      tbody.appendChild(tr);
    });

    tbody.querySelectorAll('.btn-gizmo-npc-row').forEach(btn => {
      btn.addEventListener('click', function () {
        const id = this.getAttribute('data-id');
        const name = this.getAttribute('data-name');
        const model = this.getAttribute('data-model') || 's_m_m_dockwork_01';
        const x = parseFloat(this.getAttribute('data-x'));
        const y = parseFloat(this.getAttribute('data-y'));
        const z = parseFloat(this.getAttribute('data-z'));
        const h = parseFloat(this.getAttribute('data-h'));

        const coords = (!isNaN(x) && !isNaN(y) && !isNaN(z)) ? { x: x, y: y, z: z, heading: isNaN(h) ? 0.0 : h } : null;

        postNUI('adminStartNPCGizmo', {
          id: id,
          npc_id: id,
          name: name,
          npc_name: name,
          model: model,
          npc_model: model,
          coords: coords,
          is_npc: true,
          spawn_type: 'npc'
        });

        showAdminToast(`Ajustando NPC #${id} via Gizmo 3D... Pressione [ENTER] para confirmar!`, 'info');
      });
    });

    tbody.querySelectorAll('.btn-tp-npc').forEach(btn => {
      btn.addEventListener('click', function () {
        postNUI('adminTeleport', {
          coords: {
            x: parseFloat(this.getAttribute('data-x')),
            y: parseFloat(this.getAttribute('data-y')),
            z: parseFloat(this.getAttribute('data-z')),
            heading: parseFloat(this.getAttribute('data-h'))
          }
        });
      });
    });

    tbody.querySelectorAll('.btn-del-npc').forEach(btn => {
      btn.addEventListener('click', function () {
        const id = this.getAttribute('data-id');
        showConfirmModal('Remover NPC Despachante', `Deseja realmente remover o NPC #${id}?`, () => {
          postNUI('adminDeleteNPC', { id: id });
          delete adminData.npcs[id];
          renderNPCsTab();
          showAdminToast(`NPC #${id} removido.`);
        });
      });
    });
  }

  function saveNPCForm() {
    const npcId = document.getElementById('npc-form-id').value.trim();
    if (!npcId) {
      showAdminToast('Informe o identificador do NPC (ex: dispatcher_paleto)!', 'error');
      return;
    }

    const coords = {
      x: parseFloat(document.getElementById('npc-form-x').value) || 0.0,
      y: parseFloat(document.getElementById('npc-form-y').value) || 0.0,
      z: parseFloat(document.getElementById('npc-form-z').value) || 0.0,
      heading: parseFloat(document.getElementById('npc-form-h').value) || 0.0
    };

    const payload = {
      npc_id: npcId,
      npc_name: document.getElementById('npc-form-name').value.trim() || 'Despachante Central',
      npc_model: document.getElementById('npc-form-model').value.trim() || 's_m_m_trucker_01',
      coords: coords,
      enable_target: document.getElementById('npc-form-target') ? (document.getElementById('npc-form-target').checked ? 1 : 0) : 1
    };

    postNUI('adminSaveNPC', payload);
    adminData.npcs[npcId] = payload;
    renderNPCsTab();
    showAdminToast(`NPC #${npcId} salvo e spawnado no mapa com sucesso!`);
  }

  // ============================================================
  // UTILITÁRIO: CAPTURA DINÂMICA DE COORDENADAS
  // ============================================================
  function captureCoords(targetPrefix) {
    postNUI('adminCaptureCoords', {}).then(res => {
      if (res && res.coords) {
        const c = res.coords;
        if (targetPrefix === 'route-pickup') {
          document.getElementById('route-form-pickup-x').value = c.x.toFixed(2);
          document.getElementById('route-form-pickup-y').value = c.y.toFixed(2);
          document.getElementById('route-form-pickup-z').value = c.z.toFixed(2);
        } else if (targetPrefix === 'route-deliv') {
          document.getElementById('route-form-deliv-x').value = c.x.toFixed(2);
          document.getElementById('route-form-deliv-y').value = c.y.toFixed(2);
          document.getElementById('route-form-deliv-z').value = c.z.toFixed(2);
        } else if (targetPrefix === 'spawn') {
          document.getElementById('spawn-form-x').value = c.x.toFixed(2);
          document.getElementById('spawn-form-y').value = c.y.toFixed(2);
          document.getElementById('spawn-form-z').value = c.z.toFixed(2);
          document.getElementById('spawn-form-h').value = c.heading.toFixed(2);
        } else if (targetPrefix === 'npc') {
          document.getElementById('npc-form-x').value = c.x.toFixed(2);
          document.getElementById('npc-form-y').value = c.y.toFixed(2);
          document.getElementById('npc-form-z').value = c.z.toFixed(2);
          document.getElementById('npc-form-h').value = c.heading.toFixed(2);
        }
        showAdminToast('Posição do jogador capturada!');
      }
    });
  }

  function escapeHtml(string) {
    if (string === null || string === undefined || string === false) return '';
    return String(string)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // ============================================================
  // INICIALIZAÇÃO DE EVENTOS DO DOM
  // ============================================================
  document.addEventListener('DOMContentLoaded', function () {
    const closeBtn = document.querySelector('.admin-close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', function () {
        closeAdminPanel();
        postNUI('adminClose', {});
      });
    }

    const chkForklift = document.getElementById('offset-form-isforklift');
    const propInput = document.getElementById('offset-form-prop');
    const slotSelect = document.getElementById('offset-form-slot');
    if (chkForklift && propInput) {
      chkForklift.addEventListener('change', () => {
        if (chkForklift.checked) {
          propInput.value = 'forklift';
          propInput.disabled = true;
          if (slotSelect) slotSelect.disabled = true;
        } else {
          propInput.value = 'hei_prop_carrier_cargo_04b';
          propInput.disabled = false;
          if (slotSelect) slotSelect.disabled = false;
        }
      });
    }

    document.querySelectorAll('.admin-tab-btn').forEach(btn => {
      btn.addEventListener('click', function () {
        const tab = this.getAttribute('data-tab');
        switchTab(tab);
      });
    });

    const routesFilterBar = document.getElementById('routes-filter-bar');
    if (routesFilterBar) {
      routesFilterBar.querySelectorAll('.admin-filter-btn').forEach(btn => {
        btn.addEventListener('click', function () {
          routesFilterBar.querySelectorAll('.admin-filter-btn').forEach(b => b.classList.remove('active'));
          this.classList.add('active');
          routeFilter = this.getAttribute('data-filter') || 'all';
          renderRoutesTab();
        });
      });
    }

    const routesSearchInput = document.getElementById('routes-search-input');
    if (routesSearchInput) {
      routesSearchInput.addEventListener('input', function () {
        routeSearchQuery = this.value || '';
        renderRoutesTab();
      });
    }

    const ecoFilterBar = document.getElementById('eco-filter-bar');
    if (ecoFilterBar) {
      ecoFilterBar.querySelectorAll('.admin-filter-btn').forEach(btn => {
        btn.addEventListener('click', function () {
          ecoFilterBar.querySelectorAll('.admin-filter-btn').forEach(b => b.classList.remove('active'));
          this.classList.add('active');
          ecoFilter = this.getAttribute('data-filter') || 'all';
          renderEconomyTab();
        });
      });
    }

    const btnSaveRoute = document.getElementById('btn-save-route');
    if (btnSaveRoute) btnSaveRoute.addEventListener('click', saveRouteForm);

    const btnDelRouteForm = document.getElementById('btn-delete-route');
    if (btnDelRouteForm) {
      btnDelRouteForm.addEventListener('click', function () {
        const id = document.getElementById('route-form-id').value.trim();
        if (!id) {
          showAdminToast('Nenhuma rota selecionada para excluir.', 'error');
          return;
        }
        showConfirmModal('Excluir Rota', `Deseja realmente remover a rota #${id}?`, () => {
          postNUI('adminDeleteRoute', { id: id });
          delete adminData.customRoutes[id];
          renderRoutesTab();
          renderEconomyTab();
          clearRouteForm();
          showAdminToast(`Rota #${id} excluída com sucesso.`);
        });
      });
    }

    const btnClearRouteForm = document.getElementById('btn-clear-route');
    if (btnClearRouteForm) btnClearRouteForm.addEventListener('click', clearRouteForm);

    const btnSaveSpawn = document.getElementById('btn-save-spawn');
    if (btnSaveSpawn) btnSaveSpawn.addEventListener('click', saveSpawnForm);

    const btnStartCalib = document.getElementById('btn-start-calibration');
    if (btnStartCalib) btnStartCalib.addEventListener('click', startCalibrationTool);

    const btnSaveHomolog = document.getElementById('btn-save-homologated-prop');
    if (btnSaveHomolog) btnSaveHomolog.addEventListener('click', saveHomologatedProp);

    const btnSaveEconomy = document.getElementById('btn-save-economy');
    if (btnSaveEconomy) btnSaveEconomy.addEventListener('click', saveEconomyForm);

    const btnSaveNPC = document.getElementById('btn-save-npc');
    if (btnSaveNPC) btnSaveNPC.addEventListener('click', saveNPCForm);

    const btnNewFolder = document.getElementById('btn-new-spawn-folder');
    if (btnNewFolder) {
      btnNewFolder.addEventListener('click', function () {
        showPromptModal('Nova Pasta de Spawns', 'Nome da pasta (ex: Pátio Norte)', (clean) => {
          postNUI('adminCreateSpawnFolder', { folder_name: clean });
          if (!adminData.spawnFolders) adminData.spawnFolders = ['Geral'];
          if (!adminData.spawnFolders.includes(clean)) {
            adminData.spawnFolders.push(clean);
          }
          renderSpawnsTab();
          populateRouteSpawnFolders(clean);
          const folderSelect = document.getElementById('spawn-form-folder');
          if (folderSelect) folderSelect.value = clean;
          showAdminToast(`Pasta "${clean}" criada com sucesso!`);
        });
      });
    }

    const btnNewOffsetFolder = document.getElementById('btn-new-offset-folder');
    if (btnNewOffsetFolder) {
      btnNewOffsetFolder.addEventListener('click', function () {
        showPromptModal('Nova Categoria de Offsets', 'Nome da pasta (ex: Carga Pesada, Líquidos...)', (clean) => {
          populateOffsetFolders(clean);
          const folderSelect = document.getElementById('offset-form-folder');
          if (folderSelect) folderSelect.value = clean;
          showAdminToast(`Pasta "${clean}" criada para novos offsets!`);
        });
      });
    }

    const spawnTypeSelect = document.getElementById('spawn-form-type');
    const spawnModelInput = document.getElementById('spawn-form-model');
    if (spawnTypeSelect && spawnModelInput) {
      spawnTypeSelect.addEventListener('change', function () {
        const val = this.value;
        if (val === 'load_bay' || val === 'delivery_bay') {
          spawnModelInput.placeholder = 'Marcador DrawMarker (sem modelo 3D)';
          spawnModelInput.value = '';
          spawnModelInput.disabled = true;
        } else {
          spawnModelInput.disabled = false;
          spawnModelInput.placeholder = 'ex: hauler, trailers2, forklift...';
        }
      });
    }

    const btnGizmoSpawn = document.getElementById('btn-gizmo-spawn');
    if (btnGizmoSpawn) {
      btnGizmoSpawn.addEventListener('click', function () {
        const sType = document.getElementById('spawn-form-type')?.value || 'truck';
        const sModel = (document.getElementById('spawn-form-model')?.value || '').trim();
        const sQty = parseInt(document.getElementById('spawn-form-quantity')?.value, 10) || 1;
        const sName = (document.getElementById('spawn-form-name')?.value || '').trim();
        const sId = (document.getElementById('spawn-form-id')?.value || '').trim();
        const sFolder = (document.getElementById('spawn-form-folder')?.value || '').trim() || 'Geral';

        postNUI('adminStartSpawnGizmo', {
          spawn_type: sType,
          model: sModel,
          quantity: Math.max(1, sQty),
          base_name: sName,
          base_id: sId,
          folder_name: sFolder
        });
      });
    }

    const btnPreviewSpawns = document.getElementById('btn-preview-spawns');
    if (btnPreviewSpawns) {
      btnPreviewSpawns.addEventListener('click', function () {
        const spawnsList = Object.values(adminData.spawns || {});
        if (spawnsList.length === 0) {
          showAdminToast('Nenhum ponto de spawn cadastrado para testar.', 'error');
          return;
        }
        postNUI('adminStartPreview', { spawns: spawnsList });
      });
    }

    const btnCapPickup = document.getElementById('btn-cap-pickup');
    if (btnCapPickup) btnCapPickup.addEventListener('click', () => captureCoords('route-pickup'));

    const btnCapDeliv = document.getElementById('btn-cap-deliv');
    if (btnCapDeliv) btnCapDeliv.addEventListener('click', () => captureCoords('route-deliv'));

    const btnCapSpawn = document.getElementById('btn-cap-spawn');
    if (btnCapSpawn) btnCapSpawn.addEventListener('click', () => captureCoords('spawn'));

    const btnCapNPC = document.getElementById('btn-cap-npc');
    if (btnCapNPC) btnCapNPC.addEventListener('click', () => captureCoords('npc'));

    const btnGizmoNPC = document.getElementById('btn-gizmo-npc');
    if (btnGizmoNPC) {
      btnGizmoNPC.addEventListener('click', function () {
        const npcId = (document.getElementById('npc-form-id')?.value || '').trim();
        const npcName = (document.getElementById('npc-form-name')?.value || '').trim() || 'Despachante Central';
        const npcModel = (document.getElementById('npc-form-model')?.value || '').trim() || 's_m_m_dockwork_01';

        const x = parseFloat(document.getElementById('npc-form-x')?.value);
        const y = parseFloat(document.getElementById('npc-form-y')?.value);
        const z = parseFloat(document.getElementById('npc-form-z')?.value);
        const h = parseFloat(document.getElementById('npc-form-h')?.value);

        const coords = (!isNaN(x) && !isNaN(y) && !isNaN(z)) ? { x: x, y: y, z: z, heading: isNaN(h) ? 0.0 : h } : null;

        postNUI('adminStartNPCGizmo', {
          id: npcId,
          npc_id: npcId,
          name: npcName,
          npc_name: npcName,
          model: npcModel,
          npc_model: npcModel,
          coords: coords,
          is_npc: true,
          spawn_type: 'npc'
        });

        showAdminToast('Posicionando NPC com Gizmo 3D... Pressione [ENTER] para salvar ou [ESC] para cancelar.', 'info');
      });
    }

    // ============================================================
    // CONTROLES DA ABA PROP EDITOR (6DoF)
    // ============================================================
    const btnPropSpawn = document.getElementById('btn-propeditor-spawn');
    if (btnPropSpawn) {
      btnPropSpawn.addEventListener('click', function () {
        const vModel = (document.getElementById('propeditor-vehicle-model')?.value || '').trim();
        const pModel = (document.getElementById('propeditor-prop-model')?.value || '').trim();

        if (!vModel || !pModel) {
          showAdminToast('Preencha os modelos do veículo e do prop.', 'error');
          return;
        }

        updatePropEditorStatus({ text: 'Gerando, acoplando e ativando Gizmo 3D...', type: 'attached' });
        postNUI('adminPropEditorSpawn', {
          vehicleModel: vModel,
          propModel: pModel
        });
      });
    }

    const btnPropForceAttach = document.getElementById('btn-propeditor-force-attach');
    if (btnPropForceAttach) {
      btnPropForceAttach.addEventListener('click', function () {
        postNUI('adminPropEditorForceAttach', {});
      });
    }

    const btnPropCancel = document.getElementById('btn-propeditor-cancel-session');
    if (btnPropCancel) {
      btnPropCancel.addEventListener('click', function () {
        postNUI('adminPropEditorCancel', {});
        updatePropEditorStatus({ text: 'Sessão cancelada.', type: 'info' });
        const forceBtn = document.getElementById('btn-propeditor-force-attach');
        const cancelBtn = document.getElementById('btn-propeditor-cancel-session');
        if (forceBtn) forceBtn.style.display = 'none';
        if (cancelBtn) cancelBtn.style.display = 'none';
      });
    }

    const btnPropSave = document.getElementById('btn-propeditor-save');
    if (btnPropSave) {
      btnPropSave.addEventListener('click', function () {
        const vModel = (document.getElementById('propeditor-vehicle-model')?.value || '').trim();
        const pModel = (document.getElementById('propeditor-prop-model')?.value || '').trim();

        if (!vModel || !pModel) {
          showAdminToast('Modelos do veículo e do prop são obrigatórios.', 'error');
          return;
        }

        const x = parseFloat(document.getElementById('propeditor-val-x')?.value) || 0.0;
        const y = parseFloat(document.getElementById('propeditor-val-y')?.value) || 0.0;
        const z = parseFloat(document.getElementById('propeditor-val-z')?.value) || 0.0;
        const pitch = parseFloat(document.getElementById('propeditor-val-pitch')?.value) || 0.0;
        const roll = parseFloat(document.getElementById('propeditor-val-roll')?.value) || 0.0;
        const yaw = parseFloat(document.getElementById('propeditor-val-yaw')?.value) || 0.0;

        postNUI('adminPropEditorSave', {
          vehicleModel: vModel,
          propModel: pModel,
          x: x,
          y: y,
          z: z,
          pitch: pitch,
          roll: roll,
          yaw: yaw
        });

        showAdminToast('Offsets de Prop enviados para gravação imediata no servidor!');
      });
    }

    // Sincronização dos inputs numéricos em tempo real para o Gizmo Lua
    ['propeditor-val-x', 'propeditor-val-y', 'propeditor-val-z', 'propeditor-val-pitch', 'propeditor-val-roll', 'propeditor-val-yaw'].forEach(id => {
      const el = document.getElementById(id);
      if (el) {
        el.addEventListener('input', function () {
          const x = parseFloat(document.getElementById('propeditor-val-x')?.value) || 0.0;
          const y = parseFloat(document.getElementById('propeditor-val-y')?.value) || 0.0;
          const z = parseFloat(document.getElementById('propeditor-val-z')?.value) || 0.0;
          const pitch = parseFloat(document.getElementById('propeditor-val-pitch')?.value) || 0.0;
          const roll = parseFloat(document.getElementById('propeditor-val-roll')?.value) || 0.0;
          const yaw = parseFloat(document.getElementById('propeditor-val-yaw')?.value) || 0.0;

          postNUI('adminPropEditorManualChange', {
            x: x, y: y, z: z,
            pitch: pitch, roll: roll, yaw: yaw
          });
        });
      }
    });
  });

  // ============================================================
  // FUNÇÕES DE STATUS E RENDERIZAÇÃO DA ABA PROP EDITOR
  // ============================================================
  function updatePropEditorStatus(statusObj) {
    const badge = document.getElementById('propeditor-status-badge');
    const forceBtn = document.getElementById('btn-propeditor-force-attach');
    const cancelBtn = document.getElementById('btn-propeditor-cancel-session');

    if (!badge) return;

    const text = statusObj.text || statusObj.message || 'Pronto';
    const type = statusObj.type || 'info';

    if (type === 'waiting_attach') {
      badge.style.background = 'rgba(234, 179, 8, 0.2)';
      badge.style.borderColor = '#eab308';
      badge.style.color = '#fef08a';
      badge.innerHTML = `<i class="fas fa-link fa-spin"></i> ${text}`;
      if (forceBtn) forceBtn.style.display = 'inline-flex';
      if (cancelBtn) cancelBtn.style.display = 'inline-flex';
    } else if (type === 'attached' || type === 'success') {
      badge.style.background = 'rgba(16, 185, 129, 0.2)';
      badge.style.borderColor = '#10b981';
      badge.style.color = '#6ee7b7';
      badge.innerHTML = `<i class="fas fa-check-circle"></i> ${text}`;
      if (forceBtn) forceBtn.style.display = 'none';
      if (cancelBtn) cancelBtn.style.display = 'inline-flex';
    } else if (type === 'error') {
      badge.style.background = 'rgba(239, 68, 68, 0.2)';
      badge.style.borderColor = '#ef4444';
      badge.style.color = '#fca5a5';
      badge.innerHTML = `<i class="fas fa-exclamation-triangle"></i> ${text}`;
    } else {
      badge.style.background = 'rgba(100, 116, 139, 0.2)';
      badge.style.borderColor = '#64748b';
      badge.style.color = '#94a3b8';
      badge.innerHTML = `<i class="fas fa-info-circle"></i> ${text}`;
    }
  }

  function updatePropEditorValues(data) {
    if (!data) return;
    const sx = document.getElementById('propeditor-val-x');
    const sy = document.getElementById('propeditor-val-y');
    const sz = document.getElementById('propeditor-val-z');
    const sp = document.getElementById('propeditor-val-pitch');
    const sr = document.getElementById('propeditor-val-roll');
    const syaw = document.getElementById('propeditor-val-yaw');

    if (sx && data.x != null) sx.value = parseFloat(data.x).toFixed(3);
    if (sy && data.y != null) sy.value = parseFloat(data.y).toFixed(3);
    if (sz && data.z != null) sz.value = parseFloat(data.z).toFixed(3);
    if (sp && data.pitch != null) sp.value = parseFloat(data.pitch).toFixed(1);
    if (sr && data.roll != null) sr.value = parseFloat(data.roll).toFixed(1);
    if (syaw && data.yaw != null) syaw.value = parseFloat(data.yaw).toFixed(1);
  }

  function renderPropEditorTab() {
    const tbody = document.getElementById('propeditor-table-body');
    if (!tbody) return;
    tbody.innerHTML = '';

    const list = [];
    const offsets = adminData.vehiclePropOffsets || {};

    for (const vModel in offsets) {
      const propGroup = offsets[vModel];
      if (typeof propGroup === 'object') {
        for (const pModel in propGroup) {
          const entry = propGroup[pModel];
          if (entry) {
            list.push(entry);
          }
        }
      }
    }

    if (list.length === 0) {
      tbody.innerHTML = `<tr><td colspan="6" style="text-align:center; color:#64748b; padding:24px;">Nenhum offset customizado de veículo/prop cadastrado ainda.</td></tr>`;
      return;
    }

    list.sort((a, b) => (a.vehicle_model || '').localeCompare(b.vehicle_model || ''));

    list.forEach(item => {
      const tr = document.createElement('tr');
      const x = parseFloat(item.offset_x || 0).toFixed(2);
      const y = parseFloat(item.offset_y || 0).toFixed(2);
      const z = parseFloat(item.offset_z || 0).toFixed(2);
      const p = parseFloat(item.rot_pitch || 0).toFixed(1);
      const r = parseFloat(item.rot_roll || 0).toFixed(1);
      const yw = parseFloat(item.rot_yaw || 0).toFixed(1);

      tr.innerHTML = `
        <td style="font-weight:600; color:#cbd5e1;">#${item.id || '-'}</td>
        <td style="color:#38bdf8; font-weight:600;"><i class="fas fa-truck"></i> ${item.vehicle_model}</td>
        <td style="color:#f59e0b; font-weight:600;"><i class="fas fa-box"></i> ${item.prop_model}</td>
        <td><code style="color:#38bdf8;">X: ${x} | Y: ${y} | Z: ${z}</code></td>
        <td><code style="color:#34d399;">P: ${p}° | R: ${r}° | Y: ${yw}°</code></td>
        <td style="text-align:center; white-space:nowrap;">
          <div style="display:inline-flex; gap:6px; justify-content:center; align-items:center;">
            <button class="admin-btn admin-btn-outline" onclick="loadPropEditorData('${item.vehicle_model}', '${item.prop_model}', ${x}, ${y}, ${z}, ${p}, ${r}, ${yw})" title="Carregar no Editor">
              <i class="fas fa-edit"></i>
            </button>
            <button class="admin-btn admin-btn-danger" onclick="deletePropEditorData(${item.id || 0}, '${item.vehicle_model}', '${item.prop_model}')" title="Excluir">
              <i class="fas fa-trash"></i>
            </button>
          </div>
        </td>
      `;
      tbody.appendChild(tr);
    });
  }

  window.loadPropEditorData = function (vModel, pModel, x, y, z, p, r, yw) {
    const vm = document.getElementById('propeditor-vehicle-model');
    const pm = document.getElementById('propeditor-prop-model');
    if (vm) vm.value = vModel;
    if (pm) pm.value = pModel;

    updatePropEditorValues({ x: x, y: y, z: z, pitch: p, roll: r, yaw: yw });
    showAdminToast(`Offset ${vModel} + ${pModel} carregado nos controles.`);
  };

  window.deletePropEditorData = function (id, vModel, pModel) {
    showConfirmModal(
      'Excluir Offset 6DOF',
      `Deseja excluir o offset de ${vModel} + ${pModel}?`,
      () => {
        postNUI('adminDeleteVehiclePropOffset', { id: id, vehicleModel: vModel, propModel: pModel });
        showAdminToast('Solicitação de exclusão enviada.');
      }
    );
  };

})();
