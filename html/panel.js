let config = {};

// Hard Escape Listener (Prevenção de NUI Deadlock)
window.addEventListener("keydown", function (e) {
    if (e.key === "Escape" || e.keyCode === 27) {
        $(".main").fadeOut(150);
        if (typeof Utils !== "undefined" && Utils.post) {
            Utils.post("escapeNui", {});
        } else {
            fetch(`https://${GetParentResourceName()}/escapeNui`, {
                method: "POST",
                headers: { "Content-Type": "application/json; charset=UTF-8" },
                body: JSON.stringify({})
            }).catch(() => {});
        }
    }
});

window.addEventListener("message", async function (event) {
    let item = event.data;
    if (!item) return;

    if (item.action === "close" || item.action === "close_all" || item.hidemenu) {
        $(".main").fadeOut(200);
        return;
    }

    if (item.resourceName) {
        Utils.setResourceName(item.resourceName);
    }

    let activeLocale = (item.utils && item.utils.config && item.utils.config.locale)
        || (item.dados && item.dados.config && item.dados.config.locale)
        || (item.dados && item.dados.locale)
        || item.locale
        || (config && config.locale)
        || "br";
    let activeFormat = (item.utils && item.utils.config && item.utils.config.format)
        || (item.dados && item.dados.config && item.dados.config.format)
        || (item.dados && item.dados.format)
        || item.format
        || (config && config.format)
        || { currency: "USD", location: activeLocale === "br" ? "pt-BR" : "en-US" };

    Utils.setLocale(activeLocale);
    Utils.setFormat(activeFormat);

    if (item.action === "partyUpdate") {
        if (item.party) {
            renderLationParty(item.party, item.party.members_list || item.party.members || []);
        } else {
            renderLationParty(null, []);
        }
        return;
    }

    if (item.action === "openCargoManifest") {
        openContractConfigModal(item.contractId, item.party, item.baseReward);
        return;
    }

    if (item.showmenu || item.action === "open" || item.update) {
        let dados = item.dados || item;
        config = dados.config || {};
        config.locale = config.locale || activeLocale;
        config.format = config.format || activeFormat;
        config.cooldown = config.cooldown || 2;
        config.max_emprestimo = config.max_emprestimo || 400000;
        config.player_level = config.player_level || 0;
        config.required_xp_to_levelup = config.required_xp_to_levelup || [100, 250, 450, 700, 1000, 1500, 2200, 3000, 4000, 5200];
        config.party = config.party || { price_to_create: 500, max_members: 4, price_per_member: 100 };
        config.loans = config.loans || { plans: [], payment_interval_hours: 24 };
        config.loans.plans = config.loans.plans || [];
        config.loans.payment_interval_hours = config.loans.payment_interval_hours || 24;
        config.dealership = config.dealership || {};
        config.repair_price = config.repair_price || { engine: 100, transmission: 100, wheels: 100, body: 100, fuel: 10 };

        let rawContracts = Array.isArray(dados.trucker_available_contracts) && dados.trucker_available_contracts.length > 0
            ? dados.trucker_available_contracts
            : (Array.isArray(dados.contracts) && dados.contracts.length > 0
                ? dados.contracts
                : (Array.isArray(item.jobs) && item.jobs.length > 0
                    ? item.jobs
                    : (Array.isArray(dados.jobs) && dados.jobs.length > 0 ? dados.jobs : [])));

        let contracts = rawContracts.map((c, idx) => {
            return {
                contract_id: c.contract_id ?? c.id ?? (idx + 1),
                contract_name: c.contract_name || ((c.originName && c.destName) ? `${c.originName} -> ${c.destName}` : (c.cargoItem || `Contrato #${idx + 1}`)),
                contract_type: c.contract_type ?? (idx % 2 === 0 ? 0 : 1),
                distance: Number(c.distance) || 3.5,
                reward: Number(c.reward || c.basePayment) || 1200,
                truck: c.truck || 'hauler',
                trailer: c.trailer || c.trailerModel || 'docktrailer',
                cargo_type: Number(c.cargo_type) || 0,
                fragile: Number(c.fragile) || 0,
                valuable: Number(c.valuable) || 0,
                fast: Number(c.fast) || 0,
                illegal: Number(c.illegal) || 0,
                locked: Boolean(c.locked),
                lock_type: c.lock_type || null,
                lock_reason: c.lock_reason || null,
                bonus_money_pct: Number(c.bonus_money_pct) || 0,
                bonus_exp_pct: Number(c.bonus_exp_pct) || 0,
                progress: c.progress || null,
                external_data: c.external_data || null,
            };
        });

        let users = dados.trucker_users || {
            user_id: 1, money: (dados.available_money ?? item.playerMoney ?? 0), total_earned: 0, finished_deliveries: 0,
            exp: 0, traveled_distance: 0, skill_points: 0, dark_theme: 1
        };
        let myTrucks = Array.isArray(dados.trucker_trucks) ? dados.trucker_trucks : [];
        let drivers = Array.isArray(dados.trucker_drivers) ? dados.trucker_drivers : [];
        let top_truckers = Array.isArray(dados.top_truckers) ? dados.top_truckers : [];
        let loans = Array.isArray(dados.trucker_loans) ? dados.trucker_loans : [];
        let trucker_party_members = Array.isArray(dados.trucker_party_members) ? dados.trucker_party_members : [];
        let trucker_party = dados.trucker_party || null;

        if (item.update != true) {
            // Open on first time
            $("#sidebar-ul").empty();
            $("#sidebar-ul").append(`
			<li id="sidebar-main" onclick="openPage('main')">
				<i class="fas fa-user-circle"></i>
				<span class="tooltip">${Utils.translate("sidebar_profile")}</span>
			</li>
			<li id="sidebar-job" onclick="openPage('job')">
				<i class="fas fa-truck-loading"></i>
				<span class="tooltip">${Utils.translate("sidebar_jobs")}</span>
			</li>
			<li id="sidebar-freight" onclick="openPage('freight')">
				<i class="fas fa-dolly-flatbed"></i>
				<span class="tooltip">${Utils.translate("sidebar_jobs_2")}</span>
			</li>
			<li id="sidebar-party" onclick="openPage('party')">
				<i class="fas fa-user-group"></i>
				<span class="tooltip">${Utils.translate("sidebar_party")}</span>
			</li>
			<li id="sidebar-skills" onclick="openPage('skills')">
				<i class="fas fa-medal"></i>
				<span class="tooltip">${Utils.translate("sidebar_skills")}</span>
			</li>
			<li id="sidebar-diagnostic" onclick="openPage('diagnostic')">
				<i class="fas fa-wrench"></i>
				<span class="tooltip">${Utils.translate("sidebar_diagnostic")}</span>
			</li>
			<li id="sidebar-dealership" onclick="openPage('dealership')">
				<i class="fas fa-shopping-cart"></i>
				<span class="tooltip">${Utils.translate("sidebar_dealership")}</span>
			</li>
			<li id="sidebar-trucks" onclick="openPage('trucks')">
				<i class="fas fa-truck"></i>
				<span class="tooltip">${Utils.translate("sidebar_mytrucks")}</span>
			</li>
			<li id="sidebar-drivers-page" onclick="openPage('recruitment')">
				<i class="fas fa-user-plus"></i>
				<span class="tooltip">${Utils.translate("sidebar_driver")}</span>
			</li>
			<li id="sidebar-my-drivers-page" onclick="openPage('drivers')">
				<i class="fas fa-users"></i>
				<span class="tooltip">${Utils.translate("sidebar_mydrivers")}</span>
			</li>
			<li id="sidebar-bank" onclick="openPage('bank')">
				<i class="fas fa-university"></i>
				<span class="tooltip">${Utils.translate("sidebar_bank")}</span>
			</li>
			<li id="sidebar-close" onclick="closeUI()">
				<i class="fas fa-times"></i>
				<span class="tooltip">${Utils.translate("sidebar_close")}</span>
			</li>
			`);
            $("#main-title-div").empty();
            $("#main-title-div").append(`
				<h4 class="text-uppercase">${Utils.translate("statistics_page_title")}</h4>
				<p>${Utils.translate("statistics_page_desc")}</p>
			`);
            $("#profile-money-span").empty();
            $("#profile-money-span").append(Utils.translate("statistics_page_money"));
            $("#profile-money-earned-span").empty();
            $("#profile-money-earned-span").append(Utils.translate("statistics_page_money_earned"));
            $("#profile-deliveries-span").empty();
            $("#profile-deliveries-span").append(Utils.translate("statistics_page_deliveries"));
            $("#profile-distance-traveled-span").empty();
            $("#profile-distance-traveled-span").append(Utils.translate("statistics_page_distance"));
            $("#profile-exp-1-span").empty();
            $("#profile-exp-1-span").append(Utils.translate("statistics_page_exp"));
            $("#profile-skill-points-span").empty();
            $("#profile-skill-points-span").append(Utils.translate("statistics_page_skill"));
            $("#profile-trucks-span").empty();
            $("#profile-trucks-span").append(Utils.translate("statistics_page_trucks"));
            $("#profile-drivers-span").empty();
            $("#profile-drivers-span").append(Utils.translate("statistics_page_drivers"));

            $("#top-truckers-title-div").html(`
				<h4 class="text-uppercase">${Utils.translate("statistics_page_top_truckers")}</h4>
				<p>${Utils.translate("statistics_page_top_truckers_desc")}</p>
			`);
            $("#job-title-div").html(`
				<h4 class="text-uppercase">${Utils.translate("contract_page_title")}</h4>
				<p>${Utils.translate("contract_page_desc")}</p>
			`);

            $("#freight-title-div").html(`
				<h4 class="text-uppercase">${Utils.translate("contract_page_title_freight")}</h4>
				<p>${Utils.translate("contract_page_desc_freight")}</p>
			`);

            $("#trucks-title-div").html(`
				<h4 class="text-uppercase">${Utils.translate("trucks_page_title")}</h4>
				<p>${Utils.translate("trucks_page_desc")}</p>
			`);

            $("#drivers-title-div").html(`
				<h4 class="text-uppercase">${Utils.translate("mydrivers_page_title")}</h4>
				<p>${Utils.translate("mydrivers_page_desc")}</p>
			`);

            $("#bank-title-div").html(`
				<h4 class="text-uppercase">${Utils.translate("bank_page_title")}</h4>
				<p>${Utils.translate("bank_page_desc")}</p>
			`);

            $("#recruitment-title-div").html(`
				<h4 class="text-uppercase">${Utils.translate("drivers_page_title")}</h4>
				<p>${Utils.translate("drivers_page_desc")}</p>
			`);

            $("#dealership-title-div").html(`
				<h4 class="text-uppercase">${Utils.translate("dealership_page_title")}</h4>
				<p>${Utils.translate("dealership_page_desc")}</p>
			`);

            $("#party-title-div").html(`
				<h4 class="text-uppercase">${Utils.translate("party_page_title")}</h4>
				<p>${Utils.translate("party_page_desc")}</p>
			`);

            $("#skills-title").empty();
            $("#skills-title").append(Utils.translate("skills_page_title"));

            $("#withdraw-money-btn").text(Utils.translate("bank_page_withdraw"));
            $("#deposit-money-btn").text(Utils.translate("bank_page_deposit"));
            $("#active-loans-title").text(`${Utils.translate("bank_page_active_loans")}`);
            $("#bank-balance-text").text(`${Utils.translate("bank_page_balance")}`);
            $("#bank-loans-title").text(`${Utils.translate("bank_page_loan_title")}`);
            $("#bank-loans-desc").html(`${Utils.translate("bank_page_loan_desc").format(Utils.currencyFormat(config.max_emprestimo))}`);
            $("#bank-loans-btn").text(`${Utils.translate("bank_page_loan_button")}`);
            $("#loan-value-title").text(`${Utils.translate("bank_page_loan_value_title")}`);
            $("#loan-daily-title").text(`${Utils.translate("bank_page_loan_daily_title")}`);
            $("#loan-remaining-title").text(`${Utils.translate("bank_page_loan_remaining_title")}`);
            $("#loan-date-title").text(`${Utils.translate("bank_page_loan_date_title")}`);

            $("#loan-modal-title").text(`${Utils.translate("bank_page_loan_title")}`);
            $("#loan-modal-desc").text(`${Utils.translate("bank_page_loan_modal_desc")}`);

            let loan_list = ``;
            for (const loan_id in config.loans.plans) {
                const checkedAttribute = loan_id == 0 ? "checked" : "";
                const loan = config.loans.plans[loan_id];
                loan_list += `
					<div class="form-check mb-2">
						<input class="form-check-input" type="radio" name="loan-radio" id="loan-${loan_id}" value="${loan_id}" ${checkedAttribute}>
						<label class="form-check-label" for="loan-${loan_id}">
							<span style="font-weight: 600;">${Utils.currencyFormat(loan.loan_amount)}</span> ${Utils.translate("bank_page_loan_modal_item").format(Utils.numberFormat(loan.interest_rate),Utils.numberFormat(loan.repayment_days))}
						</label>
					</div>
				`;
            }
            $("#loan-list-container").html(loan_list);
            $("#loan-modal-cancel").text(`${Utils.translate("bank_page_modal_cancel")}`);
            $("#loan-modal-submit").text(`${Utils.translate("bank_page_loan_modal_submit")}`);

            $("#deposit-modal-title").text(`${Utils.translate("bank_page_deposit_modal_title")}`);
            $("#deposit-modal-desc").text(`${Utils.translate("bank_page_deposit_modal_desc")}`);
            $("#deposit-modal-money-amount").attr("placeholder", Utils.translate("bank_page_modal_placeholder"));
            $("#deposit-modal-cancel").text(`${Utils.translate("bank_page_modal_cancel")}`);
            $("#deposit-modal-submit").text(`${Utils.translate("bank_page_deposit_modal_submit")}`);

            $("#withdraw-modal-title").text(`${Utils.translate("bank_page_withdraw_modal_title")}`);
            $("#withdraw-modal-desc").text(`${Utils.translate("bank_page_withdraw_modal_desc")}`);
            $("#withdraw-modal-money-amount").attr("placeholder", Utils.translate("bank_page_modal_placeholder"));
            $("#withdraw-modal-cancel").text(`${Utils.translate("bank_page_modal_cancel")}`);
            $("#withdraw-modal-submit").text(`${Utils.translate("bank_page_withdraw_modal_submit")}`);

            $("#skills-description-1").empty();
            $("#skills-description-1").append(Utils.translate("skills_page_description"));
            $("#skills-description-2").empty();
            $("#skills-description-2").append(Utils.translate("skills_page_description"));
            $("#skills-description-3").empty();
            $("#skills-description-3").append(Utils.translate("skills_page_description"));
            $("#skills-description-4").empty();
            $("#skills-description-4").append(Utils.translate("skills_page_description"));
            $("#skills-description-5").empty();
            $("#skills-description-5").append(Utils.translate("skills_page_description"));
            $("#skills-description-6").empty();
            $("#skills-description-6").append(Utils.translate("skills_page_description"));
            $("#product-type-title").empty();
            $("#product-type-title").append(Utils.translate("skills_page_product_type_title"));
            $("#product-type-desc").empty();
            $("#product-type-desc").append(Utils.translate("skills_page_product_type_description"));
            $("#distance-title").empty();
            $("#distance-title").append(Utils.translate("skills_page_distance_title"));
            $("#distance-desc").empty();
            $("#distance-desc").append(Utils.translate("skills_page_distance_description"));
            $("#valuable-skill-title").empty();
            $("#valuable-skill-title").append(Utils.translate("skills_page_valuable_title"));
            $("#valuable-skill-desc").empty();
            $("#valuable-skill-desc").append(Utils.translate("skills_page_valuable_desc"));
            $("#fragile-skill-title").empty();
            $("#fragile-skill-title").append(Utils.translate("skills_page_fragile_title"));
            $("#fragile-skill-desc").empty();
            $("#fragile-skill-desc").append(Utils.translate("skills_page_fragile_desc"));
            $("#fast-skill-title").empty();
            $("#fast-skill-title").append(Utils.translate("skills_page_fast_title"));
            $("#fast-skill-desc").empty();
            $("#fast-skill-desc").append(Utils.translate("skills_page_fast_desc"));
            $("#illegal-skill-title").empty();
            $("#illegal-skill-title").append(Utils.translate("skills_page_illegal_title"));
            $("#illegal-skill-desc").empty();
            $("#illegal-skill-desc").append(Utils.translate("skills_page_illegal_desc"));

            switchPartyTab('create');

            $(".sidebar-navigation ul li").removeClass("active");
            $("#sidebar-job").addClass("active");

            if (config.disable_drivers) {
                $("#sidebar-drivers-page").css("display", "none");
                $("#sidebar-my-drivers-page").css("display", "none");
            }
            if (config.disable_loans) {
                $("#loans-card-container").removeClass("d-flex");
                $("#loans-card-container").css("display", "none");
            }

            $("#css-toggle").prop("checked", users.dark_theme).change();

            $(".main").css("display", "flex").hide().fadeIn(200);
            openPage("job");
        }

        $("#player-info-level").text(config.player_level);
        $("#player-info-skill").text(Utils.numberFormat(users.exp));
        $("#player-info-money").text(Utils.currencyFormat(users.money, 0));

        $("#diagnostic-body").empty();
        $("#diagnostic-body").append(`
			<div class="media d-flex">
				<div class="media-body text-left">
					<h3 class="text-success">100 %</h3><span>${Utils.translate("diagnostic_page_chassi")}</span>
				</div>
				<div class="align-self-center">
					<i class="fas fa-truck-field text-success font-large-2 float-right"></i>
				</div>
			</div>
			<div class="progress mt-1 mb-0" style="height: 7px;">
				<div class="progress-bar bg-success" role="progressbar" style="width: 100%" aria-valuenow="100" aria-valuemin="0" aria-valuemax="100"></div>
			</div>
		`);
        $("#diagnostic-engine").empty();
        $("#diagnostic-engine").append(`
			<div class="media d-flex">
				<div class="media-body text-left">
					<h3 class="text-success">100 %</h3><span>${Utils.translate("diagnostic_page_engine")}</span>
				</div>
				<div class="align-self-center">
					<i class="fas fa-car-battery text-success font-large-2 float-right"></i>
				</div>
			</div>
			<div class="progress mt-1 mb-0" style="height: 7px;">
				<div class="progress-bar bg-success" role="progressbar" style="width: 100%" aria-valuenow="100" aria-valuemin="0" aria-valuemax="100"></div>
			</div>
		`);
        $("#diagnostic-transmission").empty();
        $("#diagnostic-transmission").append(`
			<div class="media d-flex">
				<div class="media-body text-left">
					<h3 class="text-success">100 %</h3><span>${Utils.translate("diagnostic_page_transmission")}</span>
				</div>
				<div class="align-self-center">
					<i class="fas fa-tools text-success font-large-2 float-right"></i>
				</div>
			</div>
			<div class="progress mt-1 mb-0" style="height: 7px;">
				<div class="progress-bar bg-success" role="progressbar" style="width: 100%" aria-valuenow="100" aria-valuemin="0" aria-valuemax="100"></div>
			</div>
		`);
        $("#diagnostic-wheels").empty();
        $("#diagnostic-wheels").append(`
			<div class="media d-flex">
				<div class="media-body text-left">
					<h3 class="text-success">100 %</h3><span>${Utils.translate("diagnostic_page_wheels")}</span>
				</div>
				<div class="align-self-center">
					<i class="fas fa-gear text-success font-large-2 float-right"></i>
				</div>
			</div>
			<div class="progress mt-1 mb-0" style="height: 7px;">
				<div class="progress-bar bg-success" role="progressbar" style="width: 100%" aria-valuenow="100" aria-valuemin="0" aria-valuemax="100"></div>
			</div>
		`);

        $("#diagnostic-fuel-bar").empty();
        $("#diagnostic-fuel-bar").append(`
			<div class="progress progress-bar-vertical">
				<div class="progress-bar bg-warning progress-bar-striped progress-bar-animated" role="progressbar" aria-valuenow="30" aria-valuemin="0" aria-valuemax="100" style="height: 100%;"></div>
			</div>
			<img src="img/icons/fuel.png" style="width: 40px;" class="mt-3">
		`);

        let cooldownVal = (config && config.cooldown) ? config.cooldown : 2;
        $("#new-contracts-1").empty().append(Utils.translate("new_contracts").format(cooldownVal));
        $("#new-contracts-2").empty().append(Utils.translate("new_contracts").format(cooldownVal));

        $("#profile-money").empty().append(Utils.currencyFormat(users.money, 0));
        $("#bank-money").empty().append(Utils.currencyFormat(users.money, 0));

        let availMoney = (dados && typeof dados.available_money !== "undefined") ? dados.available_money : (users.money || 0);
        $("#withdraw-modal-money-available").text(`${Utils.translate("bank_page_modal_money_available").format(Utils.currencyFormat(users.money || 0))}`);
        $("#deposit-modal-money-available").text(`${Utils.translate("bank_page_modal_money_available").format(Utils.currencyFormat(availMoney))}`);

        $("#profile-money-earned").empty().append(Utils.currencyFormat(users.total_earned || 0, 0));
        $("#profile-deliveries").empty().append(users.finished_deliveries || 0);
        $("#profile-exp-1").empty().append(Utils.numberFormat(users.exp || 0));
        $("#profile-exp-2").empty();
        let exp_r = 0;
        let xpLevels = Array.isArray(config.required_xp_to_levelup) ? config.required_xp_to_levelup : [100, 250, 450, 700, 1000, 1500, 2200, 3000, 4000, 5200];
        if (users.exp >= xpLevels[xpLevels.length - 1]) {
            exp_r = 100;
        } else if (config.player_level == 0) {
            let max = xpLevels[0] || 100;
            let exp = users.exp || 0;
            exp_r = Math.min(100, Math.max(0, Math.round((exp * 100) / max)));
        } else {
            for (let key = 0; key < xpLevels.length; key++) {
                if (users.exp < xpLevels[key]) {
                    let prev = key > 0 ? xpLevels[key - 1] : 0;
                    let max = xpLevels[key] - prev;
                    let exp = users.exp - prev;
                    exp_r = max > 0 ? Math.min(100, Math.max(0, Math.round((exp * 100) / max))) : 0;
                    break;
                }
            }
        }
        $("#profile-exp-2").append(`<div class="progress-bar bg-amber accent-4" role="progressbar" style="width: ${exp_r}%" aria-valuenow="${exp_r}" aria-valuemin="0" aria-valuemax="100"></div>`);
        $("#profile-distance-traveled").empty().append(Utils.numberFormat(users.traveled_distance || 0, 2) + "km");
        $("#profile-skill-points").empty().append(users.skill_points || 0);
        $("#profile-trucks").empty().append(myTrucks.length);
        let drivers_count = 0;
        for (const driver of drivers) {
            if (driver && driver.user_id != null && driver.user_id != undefined) {
                drivers_count++;
            }
        }
        $("#profile-drivers").empty().append(drivers_count);

        $("#top-truckers-list").empty();
        if (top_truckers.length === 0) {
            $("#top-truckers-list").html(`<li class="card-theme p-3 text-center text-muted font-small-3" style="border-radius: 8px;">Nenhum registro no ranking ainda.</li>`);
        } else {
            let c = 1;
            for (const top_users of top_truckers) {
                let icon;
                if (c == 1) {
                    icon = "fa-medal amber accent-4 font-large-2";
                } else if (c == 2) {
                    icon = "fa-medal blue-grey lighten-3 font-large-1";
                } else if (c == 3) {
                    icon = "fa-medal bronze font-large-0";
                } else {
                    icon = "fa-check-circle checkicon font-small-3";
                }
                $("#top-truckers-list").append(`
                <li class="d-flex justify-content-between card-theme">
                    <div class="d-flex flex-row align-items-center"><i class="fas ${icon}"></i>
                        <div class="ml-2">
                            <h6 class="mb-0">${top_users.name || "Motorista"} ${top_users.firstname ?? ""}</h6>
                            <div class="d-flex flex-row mt-1 text-black-50 date-time">
                                <div><i class="fas fa-route"></i><span class="ml-2">${Utils.translate("top_trucker_distance_traveled").format(Utils.numberFormat(top_users.traveled_distance || 0, 2))}</span></div>
                                <div class="ml-3"><i class="fas fa-chart-line"></i><span class="ml-2">${Utils.translate("top_trucker_exp").format(Utils.numberFormat(top_users.exp || 0))}</span></div>
                            </div>
                        </div>
                    </div>
                </li>`);
                c++;
            }
        }

        $("#job-page-list").empty();
        $("#freight-page-list").empty();
        let quick_jobs_count = 0;
        let freight_jobs_count = 0;

        for (const contract of contracts) {
            if (!contract || !contract.distance) continue;

            // Verificação de bloqueio por requisitos de habilidade (ETS2 style)
            let userProductType = Number(users.product_type || 0);
            let userDistance = Number(users.distance || 0);
            let userFragile = Number(users.fragile || 0);
            let userValuable = Number(users.valuable || 0);
            let userFast = Number(users.fast || 0);
            let userIllegal = Number(users.illegal || 0);

            let distLimits = [6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 999.0];
            let maxDistAllowed = distLimits[userDistance] || 6.0;

            let isLocked = Boolean(contract.locked);
            let lockReason = contract.lock_reason || "";

            if (!isLocked) {
                if (contract.cargo_type > 0 && userProductType < contract.cargo_type) {
                    isLocked = true;
                    lockReason = Utils.translate("contract_locked_adr").format(contract.cargo_type);
                } else if (contract.distance > maxDistAllowed) {
                    isLocked = true;
                    lockReason = Utils.translate("contract_locked_distance").format(maxDistAllowed.toFixed(1));
                } else if (contract.fragile == 1 && userFragile < 1) {
                    isLocked = true;
                    lockReason = Utils.translate("contract_locked_fragile");
                } else if (contract.valuable == 1 && userValuable < 1) {
                    isLocked = true;
                    lockReason = Utils.translate("contract_locked_valuable");
                } else if (contract.fast == 1 && userFast < 1) {
                    isLocked = true;
                    lockReason = Utils.translate("contract_locked_fast");
                } else if (contract.illegal == 1 && userIllegal < 1) {
                    isLocked = true;
                    lockReason = Utils.translate("contract_locked_illegal");
                }
            }

            let icon = "";
            let border = "";
            if (contract.external_data) {
                icon = `<i class="fas fa-trophy trophyicon"></i>`;
                border = ` style="border: 1px solid gold;"`;
            }
            if (contract.illegal == 1) {
                border = ` style="border: 1px solid #dc3545;"`;
            }
            if (isLocked) {
                border = ` style="border: 1px solid rgba(239, 68, 68, 0.4); opacity: 0.72;"`;
            }

            if (config.dealership && config.dealership[contract.truck]) {
                icon = `<img src="${config.dealership[contract.truck].img}" class="img-width" alt="${config.dealership[contract.truck].img}">`;
            } else {
                icon = `<img src="img/trucks/hauler.png" class="img-width" alt="truck">`;
            }
            icon += `<img src="img/trailers/${contract.trailer}.png" class="img-width" alt="${contract.trailer}">`;

            let partystart_btn = "";
            let button = "";

            if (isLocked) {
                button = `<button disabled type="button" class="btn btn-secondary waves-effect waves-light locked-job-btn" data-reason="${lockReason}" style="cursor: not-allowed; opacity: 0.85; background: #374151; border-color: #4b5563;" title="${lockReason}"><i class="fas fa-lock mr-1 text-danger"></i>${Utils.translate("contract_page_button_locked") || "Bloqueado"}</button>`;
            } else {
                if (typeof trucker_party !== "undefined" && trucker_party != null && !contract.external_data) {
                    partystart_btn = `<button data-id="${contract.contract_id}" data-contract-id="${contract.contract_id}" data-reward="${contract.reward || 0}" data-party="true" type="button" class="btn btn-dark waves-effect waves-light party-start-job-btn">${Utils.translate("contract_page_button_start_job_party")}</button>`;
                }
                button = `<button data-id="${contract.contract_id}" data-contract-id="${contract.contract_id}" data-reward="${contract.reward || 0}" data-party="false" type="button" class="btn btn-primary waves-effect waves-light start-job-btn">${Utils.translate("contract_page_button_start_job")}</button>`;
                if (contract.progress) {
                    button = `<button data-id="${contract.contract_id}" data-contract-id="${contract.contract_id}" onclick="cancelContract(${contract.contract_id})" type="button" class="btn btn-outline-danger waves-effect waves-light cancel-job-btn">${Utils.translate("contract_page_button_cancel_job")}</button>`;
                    partystart_btn = "";
                }
            }

            let cargo_badge = "";
            if (contract.cargo_type == 1) cargo_badge += `<div data-tooltip-location="left" data-tooltip="${Utils.translate("contract_page_cargo_explosive")}"><img src="img/icons/explosive-1.png" width="30"></div>`;
            else if (contract.cargo_type == 2) cargo_badge += `<div data-tooltip-location="left" data-tooltip="${Utils.translate("contract_page_cargo_flammablegas")}"><img src="img/icons/flamable-2.png" width="30"></div>`;
            else if (contract.cargo_type == 3) cargo_badge += `<div data-tooltip-location="left" data-tooltip="${Utils.translate("contract_page_cargo_flammableliquid")}"><img src="img/icons/flamable-3.png" width="30"></div>`;
            else if (contract.cargo_type == 4) cargo_badge += `<div data-tooltip-location="left" data-tooltip="${Utils.translate("contract_page_cargo_flammablesolid")}"><img src="img/icons/flamable-4.png" width="30"></div>`;
            else if (contract.cargo_type == 5) cargo_badge += `<div data-tooltip-location="left" data-tooltip="${Utils.translate("contract_page_cargo_toxic")}"><img src="img/icons/toxic-6.png" width="30"></div>`;
            else if (contract.cargo_type == 6) cargo_badge += `<div data-tooltip-location="left" data-tooltip="${Utils.translate("contract_page_cargo_corrosive")}"><img src="img/icons/corrosive-8.png" width="30"></div>`;

            if (contract.fragile == 1) cargo_badge += `<div data-tooltip-location="left" data-tooltip="${Utils.translate("contract_page_cargo_fragile")}"><img src="img/icons/fragile.png" width="30"></div>`;
            if (contract.valuable == 1) cargo_badge += `<div data-tooltip-location="left" data-tooltip="${Utils.translate("contract_page_cargo_valuable")}"><img src="img/icons/valuable.png" width="30"></div>`;
            if (contract.fast == 1) cargo_badge += `<div data-tooltip-location="left" data-tooltip="${Utils.translate("contract_page_cargo_urgent")}"><img src="img/icons/fast.png" width="30"></div>`;
            if (contract.illegal == 1) cargo_badge += `<div data-tooltip-location="left" data-tooltip="${Utils.translate("contract_page_cargo_illegal")}"><img src="img/icons/illegal.png" width="30"></div>`;

            let bonusBadge = (contract.bonus_money_pct && contract.bonus_money_pct > 0)
                ? `<span class="badge badge-success ml-2" style="font-size: 11px; background: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid rgba(16, 185, 129, 0.4);"><i class="fas fa-arrow-trend-up mr-1"></i>+${contract.bonus_money_pct}% $</span>`
                : "";

            let lockTag = isLocked
                ? `<span class="badge badge-danger ml-2" style="font-size: 10px; font-weight: normal; background: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid rgba(239, 68, 68, 0.4);"><i class="fas fa-lock mr-1"></i>${lockReason}</span>`
                : "";

            let item_html = `
            <ul class="list list-inline mb-2">
                <li class="d-flex justify-content-between card-theme"${border}>
                    <div class="d-flex flex-row align-items-center">${icon}
                        <div class="ml-2">
                            <h6 class="mb-0 d-flex align-items-center flex-wrap">${contract.contract_name} ${lockTag}</h6>
                            <div class="d-flex flex-row mt-1 text-black-50 date-time">
                                <div><i class="fas fa-route"></i><span class="ml-2">${Utils.translate("contract_page_distance").format(Utils.numberFormat(contract.distance, 2))}</span></div>
                                <div class="ml-3"><i class="fas fa-coins"></i><span class="ml-2">${Utils.translate("contract_page_reward").format(Utils.currencyFormat(contract.reward))}${bonusBadge}</span></div>
                            </div>
                        </div>
                    </div>
                    <div class="d-flex flex-row align-items-center">
                        <div class="d-flex flex-column mr-2">
                            <div class="profile-image">
                                ${cargo_badge}
                            </div>
                        </div>
                        <div class="btn-group" role="group">
                            ${button}
                            ${partystart_btn}
                        </div>
                    </div>
                </li>
            </ul>`;

            if (contract.contract_type == 0) {
                $("#job-page-list").append(item_html);
                quick_jobs_count++;
            } else {
                $("#freight-page-list").append(item_html);
                freight_jobs_count++;
            }
        }

        if (quick_jobs_count === 0) {
            $("#job-page-list").html(`
                <div class="card-theme p-4 text-center text-muted my-3" style="border-radius: 8px;">
                    <i class="fas fa-truck-loading mb-2" style="font-size: 32px; color: var(--accent-emerald, #10b981);"></i>
                    <p class="mb-0">Nenhum trabalho rápido disponível no momento. Aguarde a renovação dos contratos.</p>
                </div>
            `);
        }
        if (freight_jobs_count === 0) {
            $("#freight-page-list").html(`
                <div class="card-theme p-4 text-center text-muted my-3" style="border-radius: 8px;">
                    <i class="fas fa-dolly-flatbed mb-2" style="font-size: 32px; color: var(--accent-emerald, #10b981);"></i>
                    <p class="mb-0">Nenhum frete disponível no momento. Adquira um caminhão próprio na concessionária.</p>
                </div>
            `);
        }

        $("#skills-desc").empty();
        $("#skills-desc").append(Utils.translate("skills_page_desc").format(users.skill_points));
        initEts2Skills(users);

        $("#dealership-page-list").empty();
        list_item = ``;
        const sorted_dealership = Utils.sortElement(config.dealership, ["required_level", "price"]);
        for (const truck of sorted_dealership) {
            let truckIdentifier = truck.id || truck.name || "";
            let button_html = `<div class="mx-3 mt-3 mb-2"><button data-model="${truckIdentifier}" data-name="${truckIdentifier}" type="button" class="btn btn-primary btn-block buy-truck-btn"><small>${Utils.translate("dealership_page_buy_button")}</small></button></div> <small class="d-flex justify-content-center text-muted">${Utils.translate("dealership_page_bottom_text")}</small>`;
            let dealership_locked_background = "";
            if (config.player_level < truck.required_level) {
                button_html = `<div class="mx-3 mt-4 mb-2"><div class="d-flex align-items-center" style="min-height: 35px;"><i class="fa-solid fa-lock text-muted"></i><span class=" ml-2 small">${Utils.translate("trucks_page_unlock").format(truck.required_level)}</span></div></div>`;
                dealership_locked_background = "dealership-locked-background";
            }
            list_item += `
				<div class="card ${dealership_locked_background}">
					<img src="${truck.img}" class="card-img-top" width="100%">
					<div class="card-body pt-0 px-0">
						<div class="d-flex flex-row justify-content-between mb-0 mt-3 px-3"> <span class="text-muted">${Utils.translate("dealership_page_truck")}</span>
							<h6>${truck.name}</h6>
						</div>
						<hr class="mt-2 mx-3">
						<div class="d-flex flex-row justify-content-between px-3 pb-4">
							<div class="d-flex flex-column"><span class="text-muted">${Utils.translate("dealership_page_price")}</span></div>
							<div class="d-flex flex-column">
								<h5 class="mb-0">${Utils.currencyFormat(truck.price)}</h5>
							</div>
						</div>
						<div class="d-flex flex-row justify-content-between p-3 card-featured-theme">
							<div class="d-flex flex-column"><small class="text-muted mb-1">${Utils.translate("dealership_page_engine")}</small>
								<div class="d-flex flex-row"><img src="img/icons/engine_icon.png" style="width:40px;">
									<div class="d-flex flex-column justify-content-center ml-1"><small class="ghj text-black-50-theme">${truck.engine}</small><small class="ghj text-black-50-theme">${truck.transmission}</small></div>
								</div>
							</div>
							<div class="d-flex flex-column"><small class="text-muted mb-2">${Utils.translate("dealership_page_power")}</small>
								<div class="d-flex flex-row"><img src="img/icons/power_icon.png" style="width:36px;">
									<h6 class="ml-1 mt-1 mb-1">${Utils.translate("dealership_page_power_value").format(truck.hp)}</h6>
								</div>
							</div>
						</div>
						${button_html}
					</div>
				</div>
				`;
        }
        $("#dealership-page-list").append(list_item);

        $("#diagnostic-title-div").html(`
			<h4 class="text-uppercase">${Utils.translate("diagnostic_page_title")} <small></small></h4>
			<p>${Utils.translate("diagnostic_page_desc")}</p>
		`);
        $("#repair-truck-img").attr("src", "img/truck_placeholder.png");

        $("#trucks-page-list").empty();
        list_item = "";
        for (const truck of myTrucks) {
            let truckInfo = (config.dealership && config.dealership[truck.truck_name]) ? config.dealership[truck.truck_name] : { name: truck.truck_name, img: "img/trucks/hauler.png" };
            truck.body = truck.body > 100 ? (truck.body / 10) : truck.body;
            truck.engine = truck.engine > 100 ? (truck.engine / 10) : truck.engine;
            truck.transmission = truck.transmission > 100 ? (truck.transmission / 10) : truck.transmission;
            truck.wheels = truck.wheels > 100 ? (truck.wheels / 10) : truck.wheels;
            if (truck.driver == 0 || truck.driver == null) {
                $("#repair-truck-img").attr("src", truckInfo.img);
                $("#diagnostic-title-div").empty();
                $("#diagnostic-title-div").append(`
					<h4 class="text-uppercase">${Utils.translate("diagnostic_page_title")} <small>(${truckInfo.name})</small></h4>
					<p>${Utils.translate("diagnostic_page_desc")}</p>
				`);
                let color;
                let bgcolor;

                if (truck.body > 80) {
                    color = "text-success";
                    bgcolor = "bg-success";
                } else if (truck.body > 40) {
                    color = "text-warning";
                    bgcolor = "bg-warning";
                } else {
                    color = "text-danger";
                    bgcolor = "bg-danger";
                }
                $("#diagnostic-body").empty();
                $("#diagnostic-body").append(`
					<div class="media d-flex">
						<div class="media-body text-left">
							<h3 class="${color}">${truck.body} %</h3><small>${Utils.translate("diagnostic_page_chassi")} (${Utils.currencyFormat((100 - truck.body) * (config.repair_price ? config.repair_price.body : 100))})</small>
						</div>
						<div class="align-self-center">
							<i class="fas fa-truck-field ${color} font-large-2 float-right"></i>
						</div>
					</div>
					<div class="progress mt-1 mb-0" style="height: 7px;">
						<div class="progress-bar ${bgcolor}" role="progressbar" style="width: ${truck.body}%" aria-valuenow="${truck.body}" aria-valuemin="0" aria-valuemax="100"></div>
					</div>
				`);

                if (truck.engine > 80) {
                    color = "text-success";
                    bgcolor = "bg-success";
                } else if (truck.engine > 40) {
                    color = "text-warning";
                    bgcolor = "bg-warning";
                } else {
                    color = "text-danger";
                    bgcolor = "bg-danger";
                }
                $("#diagnostic-engine").empty();
                $("#diagnostic-engine").append(`
					<div class="media d-flex">
						<div class="media-body text-left">
							<h3 class="${color}">${truck.engine} %</h3><small>${Utils.translate("diagnostic_page_engine")} (${Utils.currencyFormat((100 - truck.engine) * (config.repair_price ? config.repair_price.engine : 100))})</small>
						</div>
						<div class="align-self-center">
							<i class="fas fa-car-battery ${color} font-large-2 float-right"></i>
						</div>
					</div>
					<div class="progress mt-1 mb-0" style="height: 7px;">
						<div class="progress-bar ${bgcolor}" role="progressbar" style="width: ${truck.engine}%" aria-valuenow="${truck.engine}" aria-valuemin="0" aria-valuemax="100"></div>
					</div>
				`);

                if (truck.transmission > 80) {
                    color = "text-success";
                    bgcolor = "bg-success";
                } else if (truck.transmission > 40) {
                    color = "text-warning";
                    bgcolor = "bg-warning";
                } else {
                    color = "text-danger";
                    bgcolor = "bg-danger";
                }
                $("#diagnostic-transmission").empty();
                $("#diagnostic-transmission").append(`
					<div class="media d-flex">
						<div class="media-body text-left">
							<h3 class="${color}">${truck.transmission} %</h3><small>${Utils.translate("diagnostic_page_transmission")} (${Utils.currencyFormat((100 - truck.transmission) * (config.repair_price ? config.repair_price.transmission : 100))})</small>
						</div>
						<div class="align-self-center">
							<i class="fas fa-tools ${color} font-large-2 float-right"></i>
						</div>
					</div>
					<div class="progress mt-1 mb-0" style="height: 7px;">
						<div class="progress-bar ${bgcolor}" role="progressbar" style="width: ${truck.transmission}%" aria-valuenow="${truck.transmission}" aria-valuemin="0" aria-valuemax="100"></div>
					</div>
				`);

                if (truck.wheels > 80) {
                    color = "text-success";
                    bgcolor = "bg-success";
                } else if (truck.wheels > 40) {
                    color = "text-warning";
                    bgcolor = "bg-warning";
                } else {
                    color = "text-danger";
                    bgcolor = "bg-danger";
                }
                $("#diagnostic-wheels").empty();
                $("#diagnostic-wheels").append(`
					<div class="media d-flex">
						<div class="media-body text-left">
							<h3 class="${color}">${truck.wheels} %</h3><small>${Utils.translate("diagnostic_page_wheels")} (${Utils.currencyFormat((100 - truck.wheels) * (config.repair_price ? config.repair_price.wheels : 100))})</small>
						</div>
						<div class="align-self-center">
							<i class="fas fa-gear ${color} font-large-2 float-right"></i>
						</div>
					</div>
					<div class="progress mt-1 mb-0" style="height: 7px;">
						<div class="progress-bar ${bgcolor}" role="progressbar" style="width: ${truck.wheels}%" aria-valuenow="${truck.wheels}" aria-valuemin="0" aria-valuemax="100"></div>
					</div>
				`);

                $("#repair-truck-btn").empty();
                $("#repair-truck-btn").append(`<button onclick="repairTruck(${truck.truck_id})" type="button" class="btn btn-primary btn-block waves-effect waves-light">${Utils.translate("diagnostic_page_repair")}</button>`);

                let refuel_btn = ``;
                if (truck.fuel < 98) {
                    refuel_btn = `
					<span class="mt-2">${Utils.translate("diagnostic_page_refuel_label")}</span>
					<button onclick="refuelTruck(${truck.truck_id})" class="btn btn-danger mt-1">${Utils.currencyFormat((100 - truck.fuel) * (config.repair_price ? config.repair_price.fuel : 10), 0)}</button>`;
                }
                if (truck.fuel > 20) {
                    bgcolor = "bg-warning";
                } else {
                    bgcolor = "bg-danger";
                }
                $("#diagnostic-fuel-bar").empty();
                $("#diagnostic-fuel-bar").append(`
					<div class="fuel-progress-bar-container card-theme d-flex align-items-center flex-column p-3">
						<div class="progress progress-bar-vertical">
							<div class="progress-bar ${bgcolor} progress-bar-striped progress-bar-animated" role="progressbar" aria-valuenow="30" aria-valuemin="0" aria-valuemax="100" style="height: ${truck.fuel}%;"></div>
						</div>
						<img src="img/icons/fuel.png" style="width: 40px;" class="mt-3">
					</div>
					<div class="d-flex flex-column align-items-center">
						${refuel_btn}
					</div>
				`);
            }
            list_item += `
				<li class="d-flex justify-content-between card-theme">
					<div class="d-flex flex-row align-items-center"><img src="${truckInfo.img}" class="img-width" alt="Truck-Image">
						<div class="ml-2">
							<h6 class="mb-0">${truckInfo.name}</h6>
							<div class="d-flex flex-row mt-1 text-black-50 date-time">
								<div>
									<i class="fas fa-truck-field"></i><span class="ml-2">${Utils.translate("trucks_page_chassi")}: ${truck.body}%</span>
								</div>
								<div class="ml-3">
									<i class="fas fa-car-battery"></i><span class="ml-2">${Utils.translate("trucks_page_engine")}: ${truck.engine}%</span>
								</div>
								<div class="ml-3">
									<i class="fas fa-tools"></i><span class="ml-2">${Utils.translate("trucks_page_transmission")}: ${truck.transmission}%</span>
								</div>
								<div class="ml-3">
									<i class="fas fa-gear"></i><span class="ml-2">${Utils.translate("trucks_page_wheels")}: ${truck.wheels}%</span>
								</div>
								<div class="ml-3">
									<i class="fas fa-gas-pump"></i><span class="ml-2">${Utils.translate("trucks_page_fuel")}: ${truck.fuel}%</span>
								</div>
							</div>
						</div>
					</div>
					<div class="d-flex flex-row align-items-center">
						${getMyTruckHTML(truck)}
						<button onclick="sellTruck('${truck.truck_id}','${truck.truck_name}')" class="btn btn-danger">${Utils.translate("trucks_page_sell_button")}</button>
					</div>
				</li>
				`;
        }
        if (myTrucks.length === 0) {
            $("#trucks-page-list").html(`
                <div class="card-theme p-4 text-center text-muted my-3" style="border-radius: 8px;">
                    <i class="fas fa-truck mb-2" style="font-size: 32px; color: var(--accent-emerald, #10b981);"></i>
                    <p class="mb-0">Você não possui nenhum caminhão em sua frota. Visite a Concessionária para adquirir veículos.</p>
                </div>
            `);
        } else {
            $("#trucks-page-list").append(list_item);
        }

        $("#recruitment-page-list").empty();
        $("#drivers-page-list").empty();
        let recruitment_item = ``;
        let my_drivers_count = 0;
        let recruitment_count = 0;

        for (const driver of drivers) {
            if (!driver) continue;
            if (driver.user_id == null || driver.user_id == undefined) {
                recruitment_count++;
                recruitment_item += `
					<div class="card user-card">
						<div class="card-block">
							<div class="user-image">
								<img src="${driver.img || 'img/avatar/avatar1.png'}" class="img-radius" alt="User-Profile-Image">
							</div>
							<h6 class="mt-4 mb-2">${driver.name || "Candidato"}</h6>
							<p class="text-muted">${Utils.translate("drivers_page_hiring_price").format(Utils.currencyFormat(driver.price || 1000))}</p>
							<hr>
							<p class="text-muted m-0">${Utils.translate("drivers_page_product_type")}</p>
							<ul class="list-unstyled activity-leval">
								${getDriverLevelHTML(driver.product_type || 0)}
							</ul>
							<p class="text-muted m-0">${Utils.translate("drivers_page_distance")}</p>
							<ul class="list-unstyled activity-leval">
								${getDriverLevelHTML(driver.distance || 0)}
							</ul>
							<p class="text-muted m-0">${Utils.translate("drivers_page_valuable")}</p>
							<ul class="list-unstyled activity-leval">
								${getDriverLevelHTML(driver.valuable || 0)}
							</ul>
							<p class="text-muted m-0">${Utils.translate("drivers_page_fragile")}</p>
							<ul class="list-unstyled activity-leval">
								${getDriverLevelHTML(driver.fragile || 0)}
							</ul>
							<p class="text-muted m-0">${Utils.translate("drivers_page_urgent")}</p>
							<ul class="list-unstyled activity-leval">
								${getDriverLevelHTML(driver.fast || 0)}
							</ul>
							<div onclick="hireDriver('${driver.driver_id}')" class="mx-3 mt-3 mb-2"><button type="button" class="btn btn-primary btn-block"><small>${Utils.translate("drivers_page_hire_button")}</small></button></div>
						</div>
					</div>
					`;
            } else {
                my_drivers_count++;
                let fuel_color = `warning`;
                let refuel_btn = ``;
                let refuel_bar = ``;
                let truck_assigned = myTrucks.find((truck) => truck.driver == driver.driver_id);
                if (truck_assigned) {
                    if (truck_assigned.fuel < 98) {
                        refuel_btn = `<a class="dropdown-item text-black-50" onclick="refuelTruck(${truck_assigned.truck_id})">${Utils.translate("drivers_page_refuel_button").format(Utils.currencyFormat((100 - truck_assigned.fuel) * (config.repair_price ? config.repair_price.fuel : 10), 0))}</a>`;
                        if (truck_assigned.fuel < 20) {
                            fuel_color = "danger";
                        }
                    }
                    refuel_bar = `<div class="d-flex flex-row text-black-50 small">
						<div class="d-flex align-items-center mr-3">
							<img src="img/icons/fuel.png" width="35px">
							<div class="ml-1">
								<span>${Utils.translate("drivers_page_driver_fuel")}</span>
								<div id="vehicle-health" class="progress mt-0 mb-0" style="height: 10px; width: 200px;"><div class="progress-bar progress-bar-striped progress-bar-animated bg-${fuel_color}" role="progressbar" style="width: ${truck_assigned.fuel}%" aria-valuenow="0.0" aria-valuemin="0" aria-valuemax="100"></div></div>
							</div>
						</div>
					</div>`;
                }
                $("#drivers-page-list").append(`
					<li class="d-flex justify-content-between card-theme">
						<div class="d-flex flex-row align-items-center">
							<img src="${driver.img || 'img/avatar/avatar1.png'}" class="img-radius img-width" alt="User-Profile-Image">
							<div class="ml-2">
								<h6 class="mb-0">${driver.name || "Motorista"}</h6>
								<div class="d-flex flex-row mt-1 text-black-50 date-time">
									<div>
										<i class="fas fa-coins"></i><span class="ml-2">${Utils.translate("drivers_page_hiring_price").format(Utils.currencyFormat(driver.price || 1000))}</span>
									</div>
									<div class="ml-3">
										<i class="fas fa-medal"></i><span class="ml-2">${Utils.translate("drivers_page_skills")}: ${Utils.translate("drivers_page_product_type")} (${driver.product_type || 0}) ${Utils.translate("drivers_page_distance")} (${driver.distance || 0}) <BR>${Utils.translate("drivers_page_valuable")} (${driver.valuable || 0}) ${Utils.translate("drivers_page_fragile")} (${driver.fragile || 0}) ${Utils.translate("drivers_page_urgent")} (${driver.fast || 0})</span>
									</div>
								</div>
							</div>
						</div>
						<div class="d-flex flex-row align-items-center">
							${refuel_bar}
							<div class="d-flex flex-column mr-3">
								<select style="min-width:200px" id="select-truck" class="selectpicker form-control" onchange="setDriver(this.options[this.selectedIndex].getAttribute('driver_id'),this.options[this.selectedIndex].getAttribute('truck_id'));">
									${getDriverAvailableTrucksHTML(myTrucks, driver, config)}
								</select>
							</div> 
							<div class="dropdown mr-2">
								<svg data-toggle="dropdown" class="dropdown-options-svg" xmlns="http://www.w3.org/2000/svg" version="1.1" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:svgjs="http://svgjs.com/svgjs" width="512" height="512" x="0" y="0" viewBox="0 0 515.555 515.555" style="enable-background:new 0 0 512 512" xml:space="preserve"><g><path xmlns="http://www.w3.org/2000/svg" d="m496.679 212.208c25.167 25.167 25.167 65.971 0 91.138s-65.971 25.167-91.138 0-25.167-65.971 0-91.138 65.971-25.167 91.138 0" data-original="#000000" style="" class=""></path><path xmlns="http://www.w3.org/2000/svg" d="m303.347 212.208c25.167 25.167 25.167 65.971 0 91.138s-65.971 25.167-91.138 0-25.167-65.971 0-91.138 65.971-25.167 91.138 0" data-original="#000000" style="" class=""></path><path xmlns="http://www.w3.org/2000/svg" d="m110.014 212.208c25.167 25.167 25.167 65.971 0 91.138s-65.971 25.167-91.138 0-25.167-65.971 0-91.138 65.971-25.167 91.138 0" data-original="#000000" style="" class=""></path></g></svg>
								<div class="dropdown-menu">
									${refuel_btn}
									<a class="dropdown-item" onclick="fireDriver(${driver.driver_id})" style="color:#ff0000c2;">${Utils.translate("drivers_page_fire_button")}</a>
								</div>
							</div>
						</div>
					</li>
				`);
            }
        }

        if (recruitment_count > 0) {
            $("#recruitment-page-list").html(recruitment_item);
        } else {
            $("#recruitment-page-list").html(`
                <div class="col-12 card-theme p-4 text-center text-muted my-3" style="border-radius: 8px;">
                    <i class="fas fa-user-plus mb-2" style="font-size: 32px; color: var(--accent-emerald, #10b981);"></i>
                    <p class="mb-0">Nenhum motorista disponível para contratação no momento.</p>
                </div>
            `);
        }

        if (my_drivers_count === 0) {
            $("#drivers-page-list").html(`
                <div class="card-theme p-4 text-center text-muted my-3" style="border-radius: 8px;">
                    <i class="fas fa-users mb-2" style="font-size: 32px; color: var(--accent-emerald, #10b981);"></i>
                    <p class="mb-0">Você ainda não contratou nenhum motorista. Visite a Agência de Recrutamento.</p>
                </div>
            `);
        }

        $("#loan-table-body").empty();
        $("#loan-table-container").css("display", "none");
        if (loans && loans.length > 0) {
            for (const loan of loans) {
                $("#loan-table-body").append(`
                    <tr>
                        <td>${Utils.currencyFormat(loan.loan || 0)}</td>
                        <td>${Utils.currencyFormat(loan.day_cost || 0)}</td>
                        <td class="text-danger">${Utils.currencyFormat(loan.remaining_amount || 0)}</td>
                        <td>${Utils.timeConverter((loan.timer || 0)+((config.loans.payment_interval_hours || 24)*3600))}</td>
                        <td><button class="btn btn-outline-primary" style="min-width: 200px;" onclick="payLoan(${loan.id},${loan.remaining_amount})" >${Utils.translate("bank_page_loan_pay")}</button></td>
                    </tr>
                `);
                $("#loan-table-container").css("display", "");
            }
        }

        renderLationParty(trucker_party, trucker_party_members);

        $(function () {
            $(".input-pass").blur(function () {
                let PasswordVal = $("#party-password").val();
                let ConfirmPasswordVal = $("#party-password-confirm").val();
                if (PasswordVal != ConfirmPasswordVal && ConfirmPasswordVal.length > 0 && PasswordVal.length > 0) {
                    $(".ShowPasswordNotMatchesError").show();
                } else {
                    $(".ShowPasswordNotMatchesError").hide();
                }
            });
            $("#party-members").keyup(function () {
                if ($(this).val() > config.party.max_members) {
                    this.value = config.party.max_members;
                }
                if ($(this).val() && $(this).val() <= 0) {
                    this.value = 1;
                }
                $(".party-members-container span").text(Utils.currencyFormat($(this).val() * config.party.price_per_member));
                $("#submit-party-form").text(Utils.translate("party_page_finish_button").format(Utils.currencyFormat(config.party.price_to_create), Utils.currencyFormat($(this).val() * config.party.price_per_member)));
            });
        });

        $(".sidebar-navigation ul li").on("click", function () {
            $("li").removeClass("active");
            $(this).addClass("active");
        });
    }
    if (item.hidemenu) {
        $(".main").fadeOut(200);
    }
});

function getDriverLevelHTML(value) {
    let html = "";
    for (let i = 1; i <= 6; i++) {
        if (i <= value) {
            html += `<li class="actived bg-success"></li>`;
        } else {
            html += "<li></li>";
        }
    }
    return html;
}

function getDriverAvailableTrucksHTML(myTrucks, driver, config) {
    let html = "";
    let has_truck = null;
    for (const truck of myTrucks) {
        if (truck.driver == driver.driver_id) {
            has_truck = truck.truck_id;
            html += `<option selected="selected">${config.dealership[truck.truck_name].name} (+${config.dealership[truck.truck_name].driver_bonus}%)</option>`;
        } else {
            if (truck.driver == null) {
                html += `<option truck_id="${truck.truck_id}" driver_id="${driver.driver_id}">${config.dealership[truck.truck_name].name} (+${config.dealership[truck.truck_name].driver_bonus}%)</option>`;
            }
        }
    }
    if (has_truck == null) {
        html = `<option selected="selected">${Utils.translate("drivers_page_pick_truck")}</option>${html}`;
    } else {
        html = `<option driver_id="${driver.driver_id}">${Utils.translate("drivers_page_pick_truck")}</option>${html}`;
    }
    return html;
}

function getMyTruckHTML(truck) {
    return truck.driver == 0 ? `<button onclick="spawnTruck(${truck.truck_id})" class="btn btn-primary mr-2">${Utils.translate("trucks_page_spawn")}</button> <button onclick="setDriver(null,'${truck.truck_id}')" class="btn btn-outline-primary mr-2">${Utils.translate("trucks_page_remove")}</button>` : `<button onclick="setDriver('0','${truck.truck_id}')" class="btn btn-primary mr-2">${Utils.translate("trucks_page_select")}</button>`;
}

/* ============================================================
   ETS2 Driver Skills Progression System (Classic ETS2 Replica)
   ============================================================ */

const ETS2_SKILLS_INFO = {
    product_type: {
        title: "Hazardous Cargo (ADR)",
        desc: "O transporte de mercadorias perigosas exige profissionais com treinamento especial. Adquira certificações ADR para desbloquear fretes com cargas de alto risco e elevada compensação financeira.",
        ranks: [
            { heading: "Classe 1 - Explosivos", perk: "Desbloqueia cargas de dinamite, munições, pólvora e fogos de artifício." },
            { heading: "Classe 2 - Gases", perk: "Desbloqueia gases inflamáveis, não-inflamáveis e comprimidos." },
            { heading: "Classe 3 - Líquidos Inflamáveis", perk: "Desbloqueia combustíveis perigosos como gasolina, diesel e querosene." },
            { heading: "Classe 4 - Sólidos Inflamáveis", perk: "Desbloqueia fósforo, magnésio e materiais de combustão espontânea." },
            { heading: "Classe 6 - Substâncias Tóxicas", perk: "Desbloqueia venenos industriais, pesticidas e agentes biológicos." },
            { heading: "Classe 8 - Substâncias Corrosivas", perk: "Desbloqueia ácidos concentrados, hidróxidos e substâncias corrosivas." }
        ]
    },
    distance: {
        title: "Long Distance",
        desc: "Sua habilidade de longa distância determina a distância máxima que você pode viajar em serviço e garante recompensas financeiras e experiência progressivas.",
        ranks: [
            { heading: "Rank 1", perk: "Entregas até 6.5 km (+2% de pagamento e +5% de XP para rotas > 6.0 km)." },
            { heading: "Rank 2", perk: "Entregas até 7.0 km (+4% de pagamento e +10% de XP para rotas > 6.5 km)." },
            { heading: "Rank 3", perk: "Entregas até 7.5 km (+6% de pagamento e +15% de XP para rotas > 7.0 km)." },
            { heading: "Rank 4", perk: "Entregas até 8.0 km (+8% de pagamento e +20% de XP para rotas > 7.5 km)." },
            { heading: "Rank 5", perk: "Entregas até 8.5 km (+10% de pagamento e +25% de XP para rotas > 8.0 km)." },
            { heading: "Rank 6", perk: "Entregas em qualquer distância (+12% de pagamento e +30% de XP para rotas > 8.5 km)." }
        ]
    },
    valuable: {
        title: "High Value Cargo",
        desc: "Toda carga tem valor, mas algumas são de altíssimo custo. As empresas confiam apenas em motoristas certificados e experientes para transportá-las.",
        ranks: [
            { heading: "Rank 1", perk: "Desbloqueia fretes de cargas valiosas (+2% pagamento, +10% de XP)." },
            { heading: "Rank 2", perk: "Cargas de alto valor (+4% pagamento, +15% de XP)." },
            { heading: "Rank 3", perk: "Cargas de alto valor (+6% pagamento, +20% de XP)." },
            { heading: "Rank 4", perk: "Cargas de alto valor (+8% pagamento, +25% de XP)." },
            { heading: "Rank 5", perk: "Cargas de alto valor (+10% pagamento, +30% de XP)." },
            { heading: "Rank 6", perk: "Cargas de alto valor (+12% pagamento, +35% de XP)." }
        ]
    },
    fragile: {
        title: "Fragile Cargo",
        desc: "Esta especialização permite transportar cargas frágeis, como vidros nobres, eletrônicos industriais e maquinário de precisão com bônus por cuidado extra.",
        ranks: [
            { heading: "Rank 1", perk: "Desbloqueia fretes de cargas frágeis (+2% pagamento, +10% de XP)." },
            { heading: "Rank 2", perk: "Cargas frágeis (+4% pagamento, +15% de XP)." },
            { heading: "Rank 3", perk: "Cargas frágeis (+6% pagamento, +20% de XP)." },
            { heading: "Rank 4", perk: "Cargas frágeis (+8% pagamento, +25% de XP)." },
            { heading: "Rank 5", perk: "Cargas frágeis (+10% pagamento, +30% de XP)." },
            { heading: "Rank 6", perk: "Cargas frágeis (+12% pagamento, +35% de XP)." }
        ]
    },
    fast: {
        title: "Just-In-Time Delivery",
        desc: "Entregas com janela horária apertada e grande urgência. Exigem condução precisa e pontualidade sob pressão, recompensando com alto retorno.",
        ranks: [
            { heading: "Rank 1", perk: "Desbloqueia fretes de carga urgente (+2% pagamento, +10% de XP)." },
            { heading: "Rank 2", perk: "Entregas urgentes (+4% pagamento, +15% de XP)." },
            { heading: "Rank 3", perk: "Entregas urgentes (+6% pagamento, +20% de XP)." },
            { heading: "Rank 4", perk: "Entregas urgentes (+8% pagamento, +25% de XP)." },
            { heading: "Rank 5", perk: "Entregas urgentes (+10% pagamento, +30% de XP)." },
            { heading: "Rank 6", perk: "Entregas urgentes (+12% pagamento, +35% de XP)." }
        ]
    },
    illegal: {
        title: "Fuel Economy",
        desc: "Técnicas de condução eficiente e gestão de rota diminuem significativamente o consumo de combustível da sua frota em qualquer serviço.",
        ranks: [
            { heading: "Rank 1", perk: "Até 10% de economia de combustível com reboque ou livre." },
            { heading: "Rank 2", perk: "Até 15% de economia de combustível com reboque ou livre." },
            { heading: "Rank 3", perk: "Até 20% de economia de combustível com reboque ou livre." },
            { heading: "Rank 4", perk: "Até 25% de economia de combustível com reboque ou livre." },
            { heading: "Rank 5", perk: "Até 30% de economia de combustível com reboque ou livre." },
            { heading: "Rank 6", perk: "Até 35% de economia de combustível com reboque ou livre." }
        ]
    }
};

let ets2SkillsState = {
    selectedSkill: 'product_type',
    unassignedPoints: 0,
    skills: {
        product_type: 0,
        distance: 0,
        valuable: 0,
        fragile: 0,
        fast: 0,
        illegal: 0
    },
    staged: {
        product_type: 0,
        distance: 0,
        valuable: 0,
        fragile: 0,
        fast: 0,
        illegal: 0
    }
};

function initEts2Skills(usersData) {
    if (!usersData) return;
    ets2SkillsState.unassignedPoints = Number(usersData.skill_points || 0);
    ets2SkillsState.skills = {
        product_type: Math.min(6, Math.max(0, Number(usersData.product_type || 0))),
        distance: Math.min(6, Math.max(0, Number(usersData.distance || 0))),
        valuable: Math.min(6, Math.max(0, Number(usersData.valuable || 0))),
        fragile: Math.min(6, Math.max(0, Number(usersData.fragile || 0))),
        fast: Math.min(6, Math.max(0, Number(usersData.fast || 0))),
        illegal: Math.min(6, Math.max(0, Number(usersData.illegal || 0)))
    };
    ets2SkillsState.staged = {
        product_type: 0,
        distance: 0,
        valuable: 0,
        fragile: 0,
        fast: 0,
        illegal: 0
    };
    renderEts2Skills();
}

function getEts2StagedTotal() {
    let total = 0;
    for (let k in ets2SkillsState.staged) {
        total += ets2SkillsState.staged[k];
    }
    return total;
}

function getEts2AvailablePoints() {
    return Math.max(0, ets2SkillsState.unassignedPoints - getEts2StagedTotal());
}

function selectEts2Skill(skillId) {
    if (!ETS2_SKILLS_INFO[skillId]) return;
    ets2SkillsState.selectedSkill = skillId;
    renderEts2Skills();
}

function stageEts2Skill(skillId, delta, event) {
    if (event) {
        event.stopPropagation();
    }
    if (!ETS2_SKILLS_INFO[skillId]) return;

    let current = ets2SkillsState.skills[skillId] || 0;
    let staged = ets2SkillsState.staged[skillId] || 0;
    let available = getEts2AvailablePoints();

    if (delta > 0) {
        if (available > 0 && (current + staged) < 6) {
            ets2SkillsState.staged[skillId]++;
        }
    } else if (delta < 0) {
        if (staged > 0) {
            ets2SkillsState.staged[skillId]--;
        }
    }

    ets2SkillsState.selectedSkill = skillId;
    renderEts2Skills();
}

function renderEts2Skills() {
    let availablePoints = getEts2AvailablePoints();
    let stagedTotal = getEts2StagedTotal();

    // 1. Contador de pontos disponíveis
    $("#ets2-skill-points").text(availablePoints);

    // 2. Renderização das linhas de habilidades
    const skillKeys = ['product_type', 'distance', 'valuable', 'fragile', 'fast', 'illegal'];
    for (const key of skillKeys) {
        let current = ets2SkillsState.skills[key] || 0;
        let staged = ets2SkillsState.staged[key] || 0;
        let total = current + staged;

        // Seleção de linha
        let row = $("#ets2-row-" + key);
        if (key === ets2SkillsState.selectedSkill) {
            row.addClass("active");
        } else {
            row.removeClass("active");
        }

        // Botões do stepper
        let plusBtn = $("#ets2-plus-" + key);
        let minusBtn = $("#ets2-minus-" + key);

        plusBtn.prop("disabled", !(availablePoints > 0 && total < 6));
        minusBtn.prop("disabled", !(staged > 0));

        // Renderização dos blocos / diamantes
        if (key === 'product_type') {
            let adrBadges = $("#ets2-blocks-product_type .ets2-adr-badge");
            adrBadges.each(function() {
                let rank = Number($(this).attr("data-adr"));
                $(this).removeClass("unlocked pending locked");
                if (rank <= current) {
                    $(this).addClass("unlocked");
                } else if (rank <= total) {
                    $(this).addClass("pending");
                } else {
                    $(this).addClass("locked");
                }
            });
        } else {
            let blocksContainer = $("#ets2-blocks-" + key);
            blocksContainer.empty();
            for (let r = 1; r <= 6; r++) {
                let stateClass = "locked";
                if (r <= current) {
                    stateClass = "unlocked";
                } else if (r <= total) {
                    stateClass = "pending";
                }
                blocksContainer.append(`<div class="ets2-block ${stateClass}"></div>`);
            }
        }
    }

    // 3. Painel de Detalhes da Direita
    let info = ETS2_SKILLS_INFO[ets2SkillsState.selectedSkill] || ETS2_SKILLS_INFO.product_type;
    let selCurrent = ets2SkillsState.skills[ets2SkillsState.selectedSkill] || 0;
    let selStaged = ets2SkillsState.staged[ets2SkillsState.selectedSkill] || 0;
    let selTotal = selCurrent + selStaged;

    $("#ets2-detail-title").text(info.title);
    $("#ets2-detail-desc").text(info.desc);

    let ranksHtml = "";
    for (let i = 0; i < info.ranks.length; i++) {
        let rankNum = i + 1;
        let rInfo = info.ranks[i];
        let rClass = "locked";
        if (rankNum <= selCurrent) {
            rClass = "unlocked";
        } else if (rankNum <= selTotal) {
            rClass = "pending";
        }

        ranksHtml += `
            <div class="ets2-rank-item ${rClass}">
                <div class="rank-heading">${rInfo.heading}</div>
                <div class="rank-perks">${rInfo.perk}</div>
            </div>
        `;
    }
    $("#ets2-detail-ranks").html(ranksHtml);

    // 4. Botão Apply
    let applyBtn = $("#ets2-apply-btn");
    applyBtn.prop("disabled", stagedTotal === 0);
}

let isEts2Applying = false;
function applyEts2Skills() {
    if (isEts2Applying) return;
    let stagedTotal = getEts2StagedTotal();
    if (stagedTotal === 0) return;

    isEts2Applying = true;
    $("#ets2-apply-btn").prop("disabled", true);

    for (let key in ets2SkillsState.staged) {
        let count = ets2SkillsState.staged[key];
        if (count > 0) {
            let startLvl = ets2SkillsState.skills[key];
            for (let step = 1; step <= count; step++) {
                upgradeSkill(key, startLvl + step);
            }
            ets2SkillsState.skills[key] += count;
            ets2SkillsState.staged[key] = 0;
        }
    }

    ets2SkillsState.unassignedPoints -= stagedTotal;
    renderEts2Skills();

    setTimeout(() => {
        isEts2Applying = false;
    }, 1500);
}

function setSkill(id, newValue) {
    if (ets2SkillsState.skills[id] !== undefined) {
        ets2SkillsState.skills[id] = Number(newValue || 0);
        renderEts2Skills();
    }
}


function openPage(pageN) {
    $(".pages").css("display", "none");
    $(`.${pageN}-page`).css("display", "block");

    $(".sidebar-navigation ul li").removeClass("active");
    if ($(`#sidebar-${pageN}`).length) {
        $(`#sidebar-${pageN}`).addClass("active");
    } else if (pageN === "recruitment") {
        $("#sidebar-drivers-page").addClass("active");
    } else if (pageN === "drivers") {
        $("#sidebar-my-drivers-page").addClass("active");
    }

    let titleHeight = $(`#${pageN}-title-div`).outerHeight(true) ?? 0;
    let footerHeight = $(`#${pageN}-footer-div`).outerHeight(true) ?? 0;
    $(":root").css(`--${pageN}-title-height`, titleHeight + footerHeight + "px");
}

function switchPartyTab(tab) {
    if (tab === 'create') {
        $("#tab-btn-create-party").addClass("active");
        $("#tab-btn-join-party").removeClass("active");
        $("#party-tab-create").show();
        $("#party-tab-join").hide();
    } else {
        $("#tab-btn-join-party").addClass("active");
        $("#tab-btn-create-party").removeClass("active");
        $("#party-tab-join").show();
        $("#party-tab-create").hide();
    }
}

function selectPartySlots(slots) {
    $(".lation-slot-pill").removeClass("active");
    $(`.lation-slot-pill[data-slots="${slots}"]`).addClass("active");
    $("#party-members").val(slots);
}

function submitCreateParty() {
    let name = $("#party-name").val();
    let desc = $("#party-desc").val();
    let pass = $("#party-password").val() || "";
    let cpass = $("#party-password-confirm").val() || "";
    let members = parseInt($("#party-members").val()) || 4;

    if (pass && cpass && pass !== cpass) {
        $("#party-create-error").show();
        return;
    }
    $("#party-create-error").hide();

    Utils.post("createParty", { name, desc, pass, cpass, members });
}

function submitJoinParty() {
    let name = $("#party-name-join").val();
    let pass = $("#party-password-join").val() || "";

    if (!name || name.trim() === "") {
        $("#party-join-error").text("Por favor, informe o nome ou código da frota.").show();
        return;
    }
    $("#party-join-error").hide();

    Utils.post("joinParty", { name: name.trim(), pass });
}

function submitInviteParty() {
    let targetId = $("#party-invite-target-id").val();
    if (!targetId || parseInt(targetId) <= 0) {
        alert("Por favor, digite um ID de jogador válido.");
        return;
    }
    Utils.post("inviteParty", { targetId: parseInt(targetId) });
    $("#party-invite-target-id").val("");
}

function copyPartyCode(code) {
    if (!code) return;
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(code).then(() => {
            alert(`Código #${code} copiado para a área de transferência!`);
        });
    } else {
        alert(`Código da frota: #${code}`);
    }
}

function createParty() {
    switchPartyTab('create');
}

function joinParty() {
    switchPartyTab('join');
}

function renderLationParty(party, members) {
    if (!members) members = [];

    if (!party) {
        // Player has no party
        $("#party-title-div").html(`
            <div>
                <div class="lation-party-header-title"><i class="fas fa-users-gear text-emerald"></i> GRUPOS & CONVOYS</div>
                <div class="lation-party-header-desc">Crie frotas colaborativas, compartilhe fretes e viaje em comboio com outros motoristas.</div>
            </div>
        `);
        $("#party-form-container-base").show();
        $("#party-container-members").hide().empty();
        switchPartyTab('create');
        return;
    }

    // Player is in an active party
    $("#party-form-container-base").hide();
    $("#party-container-members").show().empty();

    let isOwner = party.owner == 1 || party.isLeader === true;
    let codeStr = party.code || (party.partyId ? party.partyId.substring(0, 6).toUpperCase() : (party.id ? party.id.substring(0, 6).toUpperCase() : "TRK"));
    let membersCount = party.members_count || members.length || 1;
    let maxMembers = party.members || party.maxSize || 4;

    let quitBtnStr = isOwner
        ? `<button class="lation-btn lation-btn-danger" onclick="deleteParty()"><i class="fas fa-trash-can mr-2"></i> Dissolver Frota</button>`
        : `<button class="lation-btn lation-btn-danger" onclick="quitParty()"><i class="fas fa-right-from-bracket mr-2"></i> Sair da Frota</button>`;

    // Header Overview
    let overviewHtml = `
        <div class="lation-party-overview">
            <div class="lation-party-top-row">
                <div class="lation-party-name-box">
                    <i class="fas fa-shield-halved text-emerald font-large-1"></i>
                    <div>
                        <div class="lation-party-name">${party.name || 'Frota de Logística'}</div>
                        <div class="d-flex align-items-center gap-2 mt-1">
                            <span class="lation-code-badge" onclick="copyPartyCode('${codeStr}')" title="Clique para copiar código">
                                <i class="fas fa-hashtag mr-1"></i> CÓDIGO: #${codeStr} <i class="fas fa-copy ml-1"></i>
                            </span>
                            <span class="lation-status-pill ml-2">
                                <i class="fas fa-circle-dot mr-1 text-emerald"></i> ATIVO
                            </span>
                            <span class="lation-slots-pill ml-2">
                                <i class="fas fa-users mr-1"></i> ${membersCount} / ${maxMembers} VAGAS
                            </span>
                        </div>
                    </div>
                </div>
                <div>
                    ${quitBtnStr}
                </div>
            </div>
            <p class="lation-party-desc">${party.description || 'Transporte e Logística Colaborativa'}</p>
        </div>
    `;

    // Leader Invite Bar
    let inviteBarHtml = "";
    if (isOwner) {
        inviteBarHtml = `
            <div class="lation-invite-panel">
                <div class="lation-invite-title">
                    <i class="fas fa-user-plus text-emerald mr-2"></i> CONVIDAR MOTORISTA POR ID DO SERVIDOR
                </div>
                <div class="lation-invite-form">
                    <input type="number" id="party-invite-target-id" min="1" placeholder="ID do Servidor (ex: 1, 5)" class="lation-invite-input">
                    <button type="button" class="lation-btn lation-btn-primary" onclick="submitInviteParty()">
                        <i class="fas fa-paper-plane mr-1"></i> Enviar Convite
                    </button>
                </div>
            </div>
        `;
    }

    // Members Grid
    let membersGridHtml = `
        <div class="lation-members-section-title">
            <i class="fas fa-id-card text-emerald"></i> MOTORISTAS DA FROTA (${members.length})
        </div>
        <div class="lation-members-grid">
    `;

    for (const member of members) {
        let memberIsLeader = member.owner === 1 || member.owner === true || member.isLeader === true || (party.user_id && party.user_id === member.user_id);
        let isOnline = member.online !== false;
        let onlineDotClass = isOnline ? "lation-online-dot" : "lation-online-dot offline";
        let avatarLeaderClass = memberIsLeader ? "leader-avatar" : "";

        let roleBadge = memberIsLeader
            ? `<span class="lation-role-badge leader"><i class="fas fa-crown mr-1"></i> LÍDER DA FROTA</span>`
            : `<span class="lation-role-badge member"><i class="fas fa-truck mr-1"></i> MOTORISTA</span>`;

        let kickBtn = "";
        if (isOwner && !memberIsLeader) {
            kickBtn = `<button class="lation-btn-kick" onclick="kickParty('${member.user_id || member.citizenid}')" title="Expulsar"><i class="fas fa-user-xmark mr-1"></i> Expulsar</button>`;
        }

        let deliveries = member.finished_deliveries != null ? member.finished_deliveries : 0;
        let joinedTimeStr = member.joined_at ? Utils.timeConverter(member.joined_at) : 'Ativo';

        membersGridHtml += `
            <div class="lation-member-card ${memberIsLeader ? 'is-leader-card' : ''}">
                <div class="lation-member-header">
                    <div class="lation-avatar-wrapper ${avatarLeaderClass}">
                        <i class="fas ${memberIsLeader ? 'fa-user-tie' : 'fa-user'}"></i>
                        <span class="${onlineDotClass}"></span>
                    </div>
                    <div class="lation-member-info">
                        <div class="lation-member-name" title="${member.name}">${member.name}</div>
                        ${roleBadge}
                    </div>
                </div>
                <div class="lation-member-stats">
                    <span><i class="fas fa-route mr-1 text-emerald"></i> Entregas: <strong>${deliveries}</strong></span>
                    <span><i class="fas fa-clock mr-1 text-info"></i> <strong>${joinedTimeStr}</strong></span>
                </div>
                ${kickBtn}
            </div>
        `;
    }
    membersGridHtml += `</div>`;

    $("#party-container-members").append(overviewHtml + inviteBarHtml + membersGridHtml);
}

$(document).ready(function () {
    $("#css-toggle").on("change", function () {
        if ($(this).prop("checked") == false) {
            // Light theme
            $("#css-bs-light").prop("disabled", false);
            $("#css-light").prop("disabled", false);
            $("#css-bs-dark").prop("disabled", true);
            $("#css-dark").prop("disabled", true);
            $("#dark-theme-icon").css("display", "");
            $("#light-theme-icon").css("display", "none");
            changeTheme(0);
        } else if ($(this).prop("checked") == true) {
            // Dark theme
            $("#css-bs-dark").prop("disabled", false);
            $("#css-dark").prop("disabled", false);
            $("#css-bs-light").prop("disabled", true);
            $("#css-light").prop("disabled", true);
            $("#dark-theme-icon").css("display", "none");
            $("#light-theme-icon").css("display", "");
            changeTheme(1);
        }
    });

    $("#party-form-create").on("submit", function (e) {
        e.preventDefault();
        submitCreateParty();
    });

    $("#party-form-join").on("submit", function (e) {
        e.preventDefault();
        submitJoinParty();
    });

    $("#form-deposit-money").on("submit", function (e) {
        e.preventDefault();
        let form = $("#form-deposit-money").serializeArray();
        $("#deposit-modal-money-amount").val(null);
        $("#deposit-modal").modal("hide");
        Utils.post("depositMoney", { amount: form[0].value });
    });

    $("#form-withdraw-money").on("submit", function (e) {
        e.preventDefault();
        let form = $("#form-withdraw-money").serializeArray();
        $("#withdraw-modal-money-amount").val(null);
        $("#withdraw-modal").modal("hide");
        Utils.post("withdrawMoney", { amount: form[0].value });
    });

    $("#form-loan").on("submit", function (e) {
        e.preventDefault();
        let form = $("#form-loan").serializeArray();
        $("#loans-modal").modal("hide");
        Utils.post("loan", { loan_id: form[0].value });
    });

    setInterval(function() {
        let now = Math.floor(Date.now() / 1000);
        let remaining = 120 - (now % 120);
        let mins = Math.floor(remaining / 60);
        let secs = remaining % 60;
        let timeStr = `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
        let cooldownVal = (config && config.cooldown) ? config.cooldown : 2;
        let baseText = (window.Utils && Utils.translate) ? Utils.translate("new_contracts").format(cooldownVal) : `New contracts each ${cooldownVal} min`;
        $("#new-contracts-1").text(`${baseText} (${timeStr})`);
        $("#new-contracts-2").text(`${baseText} (${timeStr})`);
    }, 1000);

    // Trava de Debounce contra duplo clique / spam
    let isActionProcessing = false;

    // Delegação de Eventos para botões gerados dinamicamente no DOM (com remoção preventiva de listeners duplicados)
    $(document).off("click", ".start-job-btn").on("click", ".start-job-btn", function(e) {
        e.preventDefault();
        e.stopPropagation();
        if (isActionProcessing || $(this).prop("disabled") || $(this).hasClass("locked-job-btn")) return;
        let id = $(this).attr("data-id") || $(this).attr("data-contract-id");
        let reward = Number($(this).attr("data-reward")) || 0;
        if (typeof id !== "undefined" && id !== null) {
            openContractConfigModal(id, false, reward);
        }
    });

    $(document).off("click", ".party-start-job-btn").on("click", ".party-start-job-btn", function(e) {
        e.preventDefault();
        e.stopPropagation();
        if (isActionProcessing || $(this).prop("disabled") || $(this).hasClass("locked-job-btn")) return;
        let id = $(this).attr("data-id") || $(this).attr("data-contract-id");
        let reward = Number($(this).attr("data-reward")) || 0;
        if (typeof id !== "undefined" && id !== null) {
            openContractConfigModal(id, true, reward);
        }
    });

    $(document).off("click", ".locked-job-btn").on("click", ".locked-job-btn", function(e) {
        e.preventDefault();
        e.stopPropagation();
        let reason = $(this).attr("data-reason") || "Requisito de habilidade não atendido.";
        if (typeof Utils !== "undefined" && Utils.customAlert) {
            Utils.customAlert(reason);
        }
    });

    $(document).off("click", ".buy-truck-btn").on("click", ".buy-truck-btn", function(e) {
        e.preventDefault();
        e.stopPropagation();
        if (isActionProcessing) return;
        let model = $(this).attr("data-model") || $(this).attr("data-name");
        if (model) {
            buyTruck(model);
        }
    });

    $(document).keyup(function (e) {
        if (e.key === "Escape" || e.keyCode === 27) {
            closeUI();
        }
    });
});

function closeUI() {
    $(".main").fadeOut(150);
    try {
        Utils.post("close", {});
    } catch(e) {}
}

let isContractStarting = false;

function updatePalletConfig(val, baseReward) {
    let count = parseInt(val) || 4;
    $("#modal-pallet-count-badge").text(`${count} Paletes`);
    let weightKg = count * 250;
    $("#modal-pallet-weight-val").text(`${weightKg.toLocaleString('pt-BR')} kg`);

    let extraPallets = Math.max(0, count - 4);
    let bonusPct = extraPallets * 15;
    if (baseReward && baseReward > 0) {
        let extraMoney = Math.floor(baseReward * (bonusPct / 100));
        $("#modal-pallet-bonus-val").text(`+${bonusPct}% (+$${extraMoney.toLocaleString('pt-BR')})`);
    } else {
        $("#modal-pallet-bonus-val").text(`+${bonusPct}%`);
    }
}

function sendNuiAction(actionName, payload) {
    let res = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : "AUST_trucker";
    let routeUrl = (typeof Utils !== "undefined" && Utils.getRoute) ? Utils.getRoute(actionName) : `https://${res}/${actionName}`;
    try {
        fetch(routeUrl, {
            method: "POST",
            headers: { "Content-Type": "application/json; charset=UTF-8" },
            body: JSON.stringify(payload || {})
        }).catch(() => {});
    } catch(e) {}
    if (typeof Utils !== "undefined" && Utils.post) {
        Utils.post(actionName, payload || {}, actionName);
    }
}

function openContractConfigModal(contract_id, party, baseReward) {
    baseReward = Number(baseReward) || 0;
    sendNuiAction("focusMenu", { id: contract_id });
    Utils.showCustomModal({
        title: "Configurar Manifesto de Carga (Estiva)",
        dialogClass: "modal-dialog modal-dialog-centered",
        bodyHtml: `
            <div class="p-2 select-none text-left">
                <p class="text-muted mb-3" style="font-size: 13px;">Defina a quantidade de paletes a estivar na caçamba e escolha se deseja embarcar a empilhadeira para autonomia de resgate.</p>
                
                <div class="card-theme p-3 mb-3" style="border-radius: 8px; border: 1px solid rgba(16,185,129,0.3);">
                    <div class="d-flex justify-content-between align-items-center mb-2">
                        <label class="mb-0 font-weight-bold text-white"><i class="fas fa-boxes-stacked mr-1 text-emerald"></i> Carga Transportada (4 a 12):</label>
                        <span id="modal-pallet-count-badge" class="badge badge-success px-2 py-1" style="font-size: 14px; background: #10b981;">4 Paletes</span>
                    </div>
                    <input type="range" class="custom-range" id="modal-pallet-slider" min="4" max="12" step="1" value="4" oninput="updatePalletConfig(this.value, ${baseReward})">
                    <div class="d-flex justify-content-between mt-1 text-muted" style="font-size: 11px;">
                        <span>4 (Mínimo)</span>
                        <span>8 (Médio)</span>
                        <span>12 (Capacidade Máxima)</span>
                    </div>
                </div>

                <div class="d-flex justify-content-between align-items-center card-theme p-3 mb-3" style="border-radius: 8px;">
                    <div>
                        <div class="font-weight-bold text-white"><i class="fas fa-weight-hanging text-emerald mr-1"></i> Peso Total da Carga:</div>
                        <div class="text-muted" style="font-size: 12px;">250 kg por palete</div>
                    </div>
                    <div id="modal-pallet-weight-val" class="font-weight-bold text-emerald" style="font-size: 16px;">1.000 kg</div>
                </div>

                <div class="d-flex justify-content-between align-items-center card-theme p-3 mb-3" style="border-radius: 8px;">
                    <div>
                        <div class="font-weight-bold text-white"><i class="fas fa-coins text-warning mr-1"></i> Bônus de Remuneração:</div>
                        <div class="text-muted" style="font-size: 12px;">+15% por palete adicional</div>
                    </div>
                    <div id="modal-pallet-bonus-val" class="font-weight-bold text-warning" style="font-size: 16px;">+0% ($0)</div>
                </div>

                <div class="card-theme p-3" style="border-radius: 8px;">
                    <div class="custom-control custom-switch">
                        <input type="checkbox" class="custom-control-input" id="modal-forklift-switch" checked>
                        <label class="custom-control-label font-weight-bold text-white" for="modal-forklift-switch">
                            Embarcar Empilhadeira (Forklift)
                        </label>
                    </div>
                    <small class="text-muted d-block mt-1">A empilhadeira viaja na traseira do trailer. Permite descer na rodovia e resgatar paletes que caírem.</small>
                </div>
            </div>
        `,
        onClose: function() {
            $(".main").hide();
            sendNuiAction("closeMenu", { id: contract_id });
        },
        buttons: [
            {
                text: "Cancelar",
                class: "btn btn-outline-secondary",
                dismiss: true,
                action: function() {
                    $(".main").hide();
                    sendNuiAction("closeMenu", { id: contract_id });
                    sendNuiAction("cancelJob", { id: contract_id });
                }
            },
            {
                text: "Confirmar & Iniciar",
                class: "btn btn-primary",
                dismiss: true,
                action: function() {
                    let pCount = parseInt($("#modal-pallet-slider").val()) || 4;
                    let fLift = $("#modal-forklift-switch").is(":checked");
                    startContract(contract_id, party, pCount, fLift);
                }
            }
        ]
    });
}

function startContract(contract_id, party, palletCount, withForklift) {
    console.log("[AUST_TRUCKER NUI] startContract acionado! ID:", contract_id, "party:", party, "pallets:", palletCount, "forklift:", withForklift);
    if (isContractStarting) {
        console.warn("[AUST_TRUCKER NUI] startContract ignorado - inicialização já em andamento.");
        return;
    }
    isContractStarting = true;
    setTimeout(() => { isContractStarting = false; }, 3000);

    // Oculta a interface imediatamente
    $(".main").hide();
    if ($("#confirmation-modal").length) {
        $("#confirmation-modal").modal("hide");
    }

    let payload = {
        id: contract_id,
        contract_id: contract_id,
        party: party,
        palletCount: palletCount || 4,
        withForklift: (typeof withForklift !== "undefined") ? withForklift : true
    };
    sendNuiAction("confirmJob", payload);
    sendNuiAction("startContract", payload);
    sendNuiAction("startJob", payload);
}

function cancelContract(contract_id) {
    Utils.post("cancelContract", { id: contract_id });
}

function sellTruck(truck_id, truck_name) {
    Utils.showDefaultDangerModal(() => Utils.post("sellTruck", { truck_id: truck_id, truck_name: truck_name }), Utils.translate("confirmation_modal_sell_vehicle"));
}

let isTruckBuying = false;

function buyTruck(truck_name) {
    if (isTruckBuying) return;
    isTruckBuying = true;
    setTimeout(() => { isTruckBuying = false; }, 2500);

    Utils.post("buyTruck", { truck_name: truck_name });
}
function spawnTruck(truck_id) {
    Utils.post("spawnTruck", { truck_id: truck_id });
}
function refuelTruck(truck_id) {
    Utils.post("refuelTruck", { truck_id: truck_id });
}
function fireDriver(driver_id) {
    Utils.post("fireDriver", { driver_id: driver_id });
}
function hireDriver(driver_id) {
    Utils.post("hireDriver", { driver_id: driver_id });
}
function upgradeSkill(id, i) {
    Utils.post("upgradeSkill", { id: id, value: i });
}
function repairTruck(id) {
    Utils.post("repairTruck", { id: id });
}
function setDriver(driver_id, truck_id) {
    Utils.post("setDriver", { driver_id: driver_id, truck_id: truck_id });
}
function changeTheme(dark_theme) {
    Utils.post("changeTheme", { dark_theme });
}
function payLoan(loan_id,remaining_amount) {
    Utils.showDefaultDangerModal(() => Utils.post("payLoan", { loan_id }), Utils.translate("confirmation_modal_loan_payoff").format(Utils.currencyFormat(remaining_amount)));
}
function kickParty(user_id) {
    Utils.post("kickParty", { user_id: user_id });
}
function deleteParty() {
    Utils.showDefaultDangerModal(() => Utils.post("deleteParty", {}), Utils.translate("confirmation_modal_delete_party"));
}
function quitParty() {
    Utils.post("quitParty", {});
}
